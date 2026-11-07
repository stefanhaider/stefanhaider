-- =====================================================================
-- Abfrage für einen Databricks SQL Alert (z. B. täglich)
-- Liefert kritische Befunde, die NEU sind (erstes Auftreten in den letzten 8 Wochen) oder in den letzten 7 Tagen
-- (bezogen auf den Vorgangsstart) aufgetreten sind.
-- Alert-Bedingung: "Anzahl Zeilen > 0" bzw. SUM(cases_last_7d) > 0.
-- Empfänger: process_owner (z. B. über Alert-Ziele je Prozess).
-- =====================================================================
WITH f AS (
  SELECT f.*, c.case_start
  FROM main.data_manager_pm.v_findings f
  JOIN main.data_manager_pm.v_case_conformance c USING (process, case_id)
  WHERE f.severity = 'kritisch'
),
ref AS (
  SELECT process, MAX(case_start) AS ref_ts   -- bei Live-Daten: current_timestamp()
  FROM main.data_manager_pm.v_case_conformance GROUP BY process
)
SELECT
  f.process,
  f.finding_type,
  f.finding,
  COUNT(DISTINCT IF(f.case_start >= r.ref_ts - INTERVAL 7 DAYS, f.case_id, NULL)) AS cases_last_7d,
  CAST(MIN(f.event_ts) AS DATE) AS first_seen,
  MIN(f.case_start) >= r.ref_ts - INTERVAL 56 DAYS AS is_new,
  array_join(slice(array_sort(collect_set(f.case_id), (a, b) -> CASE WHEN a < b THEN 1 WHEN a > b THEN -1 ELSE 0 END), 1, 5), ', ') AS example_cases,
  MAX(pc.owner) AS process_owner
FROM f
JOIN ref r USING (process)
JOIN main.data_manager_pm.process_catalog pc USING (process)
GROUP BY f.process, f.finding_type, f.finding, r.ref_ts
HAVING cases_last_7d > 0 OR is_new
ORDER BY cases_last_7d DESC;
