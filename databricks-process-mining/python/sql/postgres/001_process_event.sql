-- =====================================================================
-- Data Manager (PostgreSQL): Prozess-Footprints als append-only Tabelle
--
-- governance.process_event wird von StateMachine.transition() in DERSELBEN Transaktion wie
-- der Statuswechsel geschrieben und von Databricks über Lakehouse Federation gelesen
-- (12_federation_ingest.sql). Die Tabelle ist der dauerhafte Audit-Trail: keine Updates,
-- keine Löschungen. Archivierung nur über einen eigenen, dokumentierten Prozess (siehe unten).
--
-- Ausführung: als Migration (z. B. Alembic: op.execute(open(...).read())) durch den DB-Owner.
-- Getestet mit PostgreSQL 16 (python/tests/test_postgres.py).
-- =====================================================================
DO $$ BEGIN   -- Aktivitätsnamen enthalten Umlaute (z. B. 'Prüfung Data Owner')
    IF pg_encoding_to_char((SELECT encoding FROM pg_database WHERE datname = current_database())) <> 'UTF8' THEN
        RAISE EXCEPTION 'Datenbank % muss UTF8-kodiert sein', current_database();
    END IF;
END $$;

CREATE SCHEMA IF NOT EXISTS governance;

CREATE TABLE IF NOT EXISTS governance.process_event (
    seq              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    event_id         UUID        NOT NULL UNIQUE,
    event_type       TEXT        NOT NULL CHECK (event_type IN ('transition', 'rejected')),
    process          TEXT        NOT NULL,
    case_id          TEXT        NOT NULL,
    object_version   TEXT,
    domain           TEXT,
    from_activity    TEXT,
    activity         TEXT        NOT NULL,
    actor            TEXT        NOT NULL,
    channel          TEXT        NOT NULL CHECK (channel IN ('ui', 'api', 'admin_api', 'batch', 'migration', 'system')),
    app_version      TEXT        NOT NULL,
    workflow_version TEXT        NOT NULL,
    trace_id         TEXT,
    reason           TEXT,
    event_ts         TIMESTAMPTZ NOT NULL,                        -- fachlicher Zeitpunkt
    recorded_at      TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(), -- Schreibzeitpunkt (Wasserzeichen für Databricks)
    CONSTRAINT rejected_needs_from CHECK (event_type <> 'rejected' OR from_activity IS NOT NULL)
);

CREATE INDEX IF NOT EXISTS process_event_recorded_at_idx ON governance.process_event (recorded_at);
CREATE INDEX IF NOT EXISTS process_event_case_idx        ON governance.process_event (process, case_id, event_ts);

COMMENT ON TABLE governance.process_event IS
  'Prozess-Footprints des Data Managers (EVENT_STANDARD.md). Append-only, gelesen von Databricks.';

-- ---- append-only erzwingen (auch gegen Owner/Superuser-Skripte, die Trigger nicht umgehen) ----
CREATE OR REPLACE FUNCTION governance.process_event_append_only() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'governance.process_event ist append-only (% nicht erlaubt)', TG_OP
        USING ERRCODE = 'insufficient_privilege';
END $$;

DROP TRIGGER IF EXISTS process_event_no_update ON governance.process_event;
CREATE TRIGGER process_event_no_update BEFORE UPDATE OR DELETE ON governance.process_event
    FOR EACH ROW EXECUTE FUNCTION governance.process_event_append_only();
DROP TRIGGER IF EXISTS process_event_no_truncate ON governance.process_event;
CREATE TRIGGER process_event_no_truncate BEFORE TRUNCATE ON governance.process_event
    FOR EACH STATEMENT EXECUTE FUNCTION governance.process_event_append_only();

-- ---- Rollen: App darf nur schreiben, Databricks nur lesen --------------------------------------
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'dm_event_writer') THEN CREATE ROLE dm_event_writer NOLOGIN; END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'dm_event_reader') THEN CREATE ROLE dm_event_reader NOLOGIN; END IF;
END $$;

REVOKE ALL ON governance.process_event FROM PUBLIC;
GRANT USAGE  ON SCHEMA governance             TO dm_event_writer, dm_event_reader;
GRANT INSERT ON governance.process_event      TO dm_event_writer;   -- kein SELECT/UPDATE/DELETE nötig
GRANT SELECT ON governance.process_event      TO dm_event_reader;

-- Login-User legt der DBA an und weist die Rollen zu, z. B.:
--   CREATE ROLE datamanager_app LOGIN PASSWORD '...' IN ROLE dm_event_writer;   -- Anwendung
--   CREATE ROLE databricks_federation LOGIN PASSWORD '...' IN ROLE dm_event_reader;  -- UC-Connection
-- Empfehlung: databricks_federation auf einem Read-Replica verwenden.

-- Archivierung (falls je nötig): nur über eine dokumentierte Funktion des DB-Owners, die den
-- Trigger kontrolliert deaktiviert und nur Daten löscht, die nachweislich in Databricks liegen.
