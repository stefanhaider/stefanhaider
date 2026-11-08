-- =====================================================================
-- Data Manager (PostgreSQL): Stammdaten für das Prozess-Monitoring
--
-- Der Data Manager stellt ALLE Daten bereit, die das Databricks-Data-Product
-- "process_monitoring" braucht. Databricks liest sie read-only per Unity Catalog
-- (Foreign Catalog), zusammen mit governance.process_event (001_process_event.sql).
--
--   app_release              Releases des Data Managers                     (Quelle: Code, beim Deploy)
--   workflow_transition      Status-Maschine je Release (System-Ebene)       (Quelle: Code, beim Deploy)
--   process_catalog          Prozesse und Process Owner                      (Quelle: Governance-Modell)
--   process_model_version    freigegebene Versionen des Soll-Modells         (Quelle: Governance-Modell)
--   process_model_activity   Soll-Aktivitäten je Version                     (Quelle: Governance-Modell)
--   process_model_transition erlaubte Soll-Übergänge je Version              (Quelle: Governance-Modell)
--   governance_rule          Funktionstrennung / Fristen je Version          (Quelle: Governance-Modell)
--
-- Befüllung: `dm-sync-governance` beim Deploy (idempotent). Getestet mit PostgreSQL 16.
-- =====================================================================
CREATE SCHEMA IF NOT EXISTS governance;

CREATE TABLE IF NOT EXISTS governance.app_release (
    version     TEXT PRIMARY KEY,
    released_at TIMESTAMPTZ NOT NULL,
    notes       TEXT
);

CREATE TABLE IF NOT EXISTS governance.workflow_transition (
    release       TEXT NOT NULL REFERENCES governance.app_release (version),
    process       TEXT NOT NULL,
    src           TEXT NOT NULL,
    tgt           TEXT NOT NULL,
    since_release TEXT,
    note          TEXT,
    channels      TEXT,                       -- kommagetrennt, NULL = alle Kanäle
    PRIMARY KEY (release, process, src, tgt)
);

CREATE TABLE IF NOT EXISTS governance.process_catalog (
    process     TEXT PRIMARY KEY,
    owner       TEXT NOT NULL,
    description TEXT
);

CREATE TABLE IF NOT EXISTS governance.process_model_version (
    model_version TEXT PRIMARY KEY,
    approved_by   TEXT NOT NULL,
    approved_at   DATE NOT NULL,
    is_current    BOOLEAN NOT NULL DEFAULT false
);
CREATE UNIQUE INDEX IF NOT EXISTS process_model_version_one_current
    ON governance.process_model_version (is_current) WHERE is_current;

CREATE TABLE IF NOT EXISTS governance.process_model_activity (
    model_version TEXT NOT NULL REFERENCES governance.process_model_version (model_version),
    process       TEXT NOT NULL,
    activity      TEXT NOT NULL,
    step_order    INT  NOT NULL,
    is_terminal   BOOLEAN NOT NULL,
    is_control    BOOLEAN NOT NULL,
    PRIMARY KEY (model_version, process, activity)
);

CREATE TABLE IF NOT EXISTS governance.process_model_transition (
    model_version TEXT NOT NULL REFERENCES governance.process_model_version (model_version),
    process       TEXT NOT NULL,
    src           TEXT NOT NULL,
    tgt           TEXT NOT NULL,
    PRIMARY KEY (model_version, process, src, tgt)
);

CREATE TABLE IF NOT EXISTS governance.governance_rule (
    model_version TEXT NOT NULL REFERENCES governance.process_model_version (model_version),
    process       TEXT NOT NULL,
    rule_id       TEXT NOT NULL,
    rule_type     TEXT NOT NULL CHECK (rule_type IN ('sod', 'sla')),
    activity_a    TEXT NOT NULL,
    activity_b    TEXT NOT NULL,
    max_hours     INT,
    description   TEXT,
    severity      TEXT NOT NULL CHECK (severity IN ('kritisch', 'hoch', 'mittel')),
    PRIMARY KEY (model_version, rule_id),
    CHECK (rule_type <> 'sla' OR max_hours IS NOT NULL)
);

-- ---- Rollen: Sync beim Deploy schreibt, Databricks liest -------------------------------
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'dm_governance_sync') THEN CREATE ROLE dm_governance_sync NOLOGIN; END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'dm_event_reader')    THEN CREATE ROLE dm_event_reader NOLOGIN; END IF;
END $$;

GRANT USAGE ON SCHEMA governance TO dm_governance_sync, dm_event_reader;
GRANT SELECT, INSERT, UPDATE, DELETE ON governance.app_release, governance.workflow_transition,
      governance.process_catalog TO dm_governance_sync;
-- Soll-Modell-Versionen sind unveränderlich: nur INSERT (+ is_current umschalten)
GRANT SELECT, INSERT ON governance.process_model_version, governance.process_model_activity,
      governance.process_model_transition, governance.governance_rule TO dm_governance_sync;
GRANT UPDATE (is_current) ON governance.process_model_version TO dm_governance_sync;
GRANT SELECT ON governance.app_release, governance.workflow_transition, governance.process_catalog,
      governance.process_model_version, governance.process_model_activity,
      governance.process_model_transition, governance.governance_rule TO dm_event_reader;
