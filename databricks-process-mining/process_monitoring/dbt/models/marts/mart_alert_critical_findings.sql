-- Kritische Befunde, die NEU sind (erstes Auftreten in den letzten new_days) oder in den letzten 7 Tagen
-- (bezogen auf den Vorgangsstart) aufgetreten sind. Grundlage für den Alarm-Task im Job.
-- Bei Live-Daten kann ref_ts durch current_timestamp() ersetzt werden.
WITH f AS (
  SELECT f.*, c.case_start
  FROM {{ ref('int_findings') }} f
  JOIN {{ ref('int_case_conformance') }} c USING (process, case_id)
  WHERE f.severity = 'kritisch'
),
ref_ts_cte AS (
  SELECT process, MAX(case_start) AS ref_ts   -- bei Live-Daten: current_timestamp()
  FROM {{ ref('int_case_conformance') }} GROUP BY process
)
SELECT
  f.process,
  f.finding_type,
  f.finding,
  COUNT(DISTINCT IF(f.case_start >= r.ref_ts - INTERVAL 7 DAYS, f.case_id, NULL)) AS cases_last_7d,
  CAST(MIN(f.event_ts) AS DATE) AS first_seen,
  MIN(f.case_start) >= r.ref_ts - INTERVAL {{ var('new_days') }} DAYS AS is_new,
  array_join(slice(array_sort(collect_set(f.case_id), (a, b) -> CASE WHEN a < b THEN 1 WHEN a > b THEN -1 ELSE 0 END), 1, 5), ', ') AS example_cases,
  array_join(array_sort(collect_set(f.channel)), ', ') AS channels,
  MAX(f.system_status) AS system_status,
  MAX(pc.owner) AS process_owner
FROM f
JOIN ref_ts_cte r USING (process)
JOIN {{ ref('stg_dm__process_catalog') }} pc USING (process)
GROUP BY f.process, f.finding_type, f.finding, r.ref_ts
HAVING cases_last_7d > 0 OR is_new

