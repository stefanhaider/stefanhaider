{{
  config(
    materialized = 'incremental',
    incremental_strategy = 'merge',
    unique_key = 'event_id',
    on_schema_change = 'append_new_columns'
  )
}}
-- Inkrementelle Kopie der Prozess-Footprints aus dem Data Manager (Foreign Catalog) nach Delta.
-- Nicht "seq > max(seq)": bei parallelen Transaktionen kann eine kleinere seq später committen.
-- Daher Überlappungsfenster auf recorded_at + Deduplizierung über event_id (unique_key, MERGE).
SELECT
  CAST(seq AS BIGINT)            AS seq,
  CAST(event_id AS STRING)       AS event_id,
  event_type, process, case_id, object_version, domain, from_activity, activity, actor, channel,
  app_version, workflow_version, trace_id, reason,
  CAST(event_ts AS TIMESTAMP)    AS event_ts,
  CAST(recorded_at AS TIMESTAMP) AS recorded_at,
  current_timestamp()            AS _ingested_at
FROM {{ dm_source('process_event') }}
{% if is_incremental() %}
WHERE recorded_at >= (
  SELECT COALESCE(MAX(recorded_at), TIMESTAMP'1970-01-01') - INTERVAL {{ var('overlap_minutes') }} MINUTES
  FROM {{ this }}
)
{% endif %}
