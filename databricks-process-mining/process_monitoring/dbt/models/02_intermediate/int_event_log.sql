-- Eventlog im Format der Auswertung (eine Zeile je Event). step_no als Tie-Breaker bei gleichem Zeitstempel.
SELECT
  process, case_id,
  COALESCE(domain, 'unbekannt') AS domain,
  CAST(ROW_NUMBER() OVER (PARTITION BY process, case_id ORDER BY event_ts, seq) AS INT) AS step_no,
  event_type, from_activity, activity, actor, channel, app_version, event_ts,
  event_id, object_version, workflow_version, trace_id, reason, seq
FROM {{ ref('stg_dm__process_event') }}
