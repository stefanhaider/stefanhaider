-- =====================================================================
-- PRODUKTION: Events des Data Managers nach Databricks laden
--
--   Data Manager (Outbox) --dm-publish-events--> /Volumes/main/data_manager_pm/events/*.jsonl
--   -> event_log_bronze (Streaming Table, Auto Loader)  -> event_log (View, Spalten wie im Mockup)
--
-- event_log ersetzt dann die Beispieltabelle aus 01_sample_event_log.sql; alle Views/Datasets
-- bleiben unverändert. Ausführung als Lakeflow/DLT-Pipeline oder SQL mit Refresh-Schedule.
-- HINWEIS: Databricks-spezifisch (STREAMING TABLE, read_files) – lokal NICHT getestet.
-- =====================================================================
CREATE OR REFRESH STREAMING TABLE main.data_manager_pm.event_log_bronze
COMMENT 'Rohe Prozess-Events des Data Managers (EVENT_STANDARD.md)'
AS SELECT
  *,
  _metadata.file_path AS _source_file,
  current_timestamp() AS _ingested_at
FROM STREAM read_files(
  '/Volumes/main/data_manager_pm/events/',
  format => 'json',
  schemaHints => 'event_id STRING, event_type STRING, process STRING, case_id STRING, object_version STRING,
                  domain STRING, from_activity STRING, activity STRING, actor STRING, channel STRING,
                  app_version STRING, workflow_version STRING, trace_id STRING, event_ts TIMESTAMP, reason STRING'
);

-- Beispieltabelle aus 01 entfernen, bevor die View angelegt wird:
-- DROP TABLE IF EXISTS main.data_manager_pm.event_log;

CREATE OR REPLACE VIEW main.data_manager_pm.event_log AS
WITH dedup AS (   -- at-least-once-Auslieferung: Duplikate nach event_id entfernen
  SELECT * FROM main.data_manager_pm.event_log_bronze
  QUALIFY ROW_NUMBER() OVER (PARTITION BY event_id ORDER BY _ingested_at) = 1
)
SELECT
  process,
  case_id,
  COALESCE(domain, 'unbekannt') AS domain,
  CAST(ROW_NUMBER() OVER (PARTITION BY process, case_id ORDER BY event_ts, event_id) AS INT) AS step_no,
  event_type,
  from_activity,
  activity,
  actor,
  channel,
  app_version,
  event_ts,
  -- zusätzliche Felder für Drill-down / Application Monitoring
  event_id, object_version, workflow_version, trace_id, reason
FROM dedup;
