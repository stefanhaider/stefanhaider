-- =====================================================================
-- PRODUKTION: Prozess-Footprints aus der PostgreSQL-Datenbank des Data Managers
-- über Unity Catalog (Lakehouse Federation) nach Delta übernehmen.
--
--   Data Manager (PostgreSQL)  governance.process_event   (append-only, python/sql/postgres/001_process_event.sql)
--        │  UC-Connection + Foreign Catalog (read-only User, möglichst Read-Replica)
--        ▼
--   dm_pg.governance.process_event            (live, für Ad-hoc-Prüfungen)
--        │  MERGE alle 5–15 Min. (Databricks Job, SQL-Task)
--        ▼
--   main.data_manager_pm.process_event_bronze (Delta, vollständige Historie)
--        ▼
--   main.data_manager_pm.event_log            (View – Spalten wie 01_sample_event_log.sql;
--                                              alle Views/Datasets/Dashboards unverändert)
--
-- HINWEIS: Databricks-spezifisch (CONNECTION, FOREIGN CATALOG, MERGE, secret()) – lokal NICHT
-- getestet. Die Kopierlogik (Überlappungsfenster) ist in python/tests/test_postgres.py gegen
-- PostgreSQL 16 nachgestellt und geprüft.
-- =====================================================================

-- ---- 1) Einmalig: Connection und Foreign Catalog (Metastore-Admin bzw. CREATE CONNECTION-Recht) ----
-- Zugangsdaten als Databricks-Secrets (Scope 'data-manager'); User = databricks_federation (Rolle dm_event_reader).
CREATE CONNECTION IF NOT EXISTS dm_postgres TYPE postgresql
OPTIONS (
  host     secret('data-manager', 'pg-host'),      -- Read-Replica empfohlen
  port     '5432',
  user     secret('data-manager', 'pg-user'),
  password secret('data-manager', 'pg-password')
);

CREATE FOREIGN CATALOG IF NOT EXISTS dm_pg USING CONNECTION dm_postgres
OPTIONS (database 'datamanager');

-- Nur das Monitoring-Team und der Kopier-Job dürfen lesen (personenbezogene Daten: actor):
-- GRANT USE CATALOG ON CATALOG dm_pg TO `dm-monitoring-job`;
-- GRANT USE SCHEMA, SELECT ON SCHEMA dm_pg.governance TO `dm-monitoring-job`;

-- ---- 2) Einmalig: Delta-Zieltabelle -------------------------------------------------------
CREATE TABLE IF NOT EXISTS main.data_manager_pm.process_event_bronze (
  seq BIGINT, event_id STRING, event_type STRING, process STRING, case_id STRING, object_version STRING,
  domain STRING, from_activity STRING, activity STRING, actor STRING, channel STRING, app_version STRING,
  workflow_version STRING, trace_id STRING, reason STRING, event_ts TIMESTAMP, recorded_at TIMESTAMP,
  _ingested_at TIMESTAMP
)
COMMENT 'Prozess-Footprints des Data Managers (Kopie aus PostgreSQL, append-only)'
TBLPROPERTIES (delta.enableChangeDataFeed = true);

-- ---- 3) Wiederkehrend (Job alle 5–15 Min.): inkrementell übernehmen ------------------------
-- Warum nicht "seq > max(seq)"? Bei parallelen Transaktionen kann eine kleinere seq SPÄTER
-- committen als eine größere – eine reine seq-Grenze verliert dann Zeilen. Deshalb: alles ab
-- (letztes recorded_at − 15 Minuten) lesen und per event_id deduplizieren (idempotent).
-- Voraussetzung: keine Transaktion im Data Manager läuft länger als 15 Minuten (sonst Fenster erhöhen).
MERGE INTO main.data_manager_pm.process_event_bronze AS t
USING (
  SELECT
    seq, CAST(event_id AS STRING) AS event_id, event_type, process, case_id, object_version, domain,
    from_activity, activity, actor, channel, app_version, workflow_version, trace_id, reason,
    CAST(event_ts AS TIMESTAMP) AS event_ts, CAST(recorded_at AS TIMESTAMP) AS recorded_at
  FROM dm_pg.governance.process_event
  WHERE recorded_at >= (
    SELECT COALESCE(MAX(recorded_at), TIMESTAMP'1970-01-01') - INTERVAL 15 MINUTES
    FROM main.data_manager_pm.process_event_bronze
  )
) AS s
ON t.event_id = s.event_id
WHEN NOT MATCHED THEN INSERT (
  seq, event_id, event_type, process, case_id, object_version, domain, from_activity, activity, actor,
  channel, app_version, workflow_version, trace_id, reason, event_ts, recorded_at, _ingested_at
) VALUES (
  s.seq, s.event_id, s.event_type, s.process, s.case_id, s.object_version, s.domain, s.from_activity,
  s.activity, s.actor, s.channel, s.app_version, s.workflow_version, s.trace_id, s.reason, s.event_ts,
  s.recorded_at, current_timestamp()
);

-- ---- 4) Einmalig: event_log als View (ersetzt die Beispieltabelle aus 01) -------------------
-- DROP TABLE IF EXISTS main.data_manager_pm.event_log;     -- Beispieldaten entfernen
CREATE OR REPLACE VIEW main.data_manager_pm.event_log AS
SELECT
  process,
  case_id,
  COALESCE(domain, 'unbekannt') AS domain,
  CAST(ROW_NUMBER() OVER (PARTITION BY process, case_id ORDER BY event_ts, seq) AS INT) AS step_no,
  event_type,
  from_activity,
  activity,
  actor,
  channel,
  app_version,
  event_ts,
  event_id, object_version, workflow_version, trace_id, reason, seq   -- für Drill-down / Application Monitoring
FROM main.data_manager_pm.process_event_bronze;

-- ---- 5) Kontrolle: Vollständigkeit (z. B. täglich als SQL Alert, Bedingung: missing > 0) ----
-- SELECT COUNT(*) AS missing
-- FROM dm_pg.governance.process_event p
-- LEFT ANTI JOIN main.data_manager_pm.process_event_bronze b ON b.event_id = CAST(p.event_id AS STRING)
-- WHERE p.recorded_at < current_timestamp() - INTERVAL 1 HOUR;
