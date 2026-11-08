-- =====================================================================
-- Dataset "findings_summary" – ein Datensatz je Befund (Prozess + Befund)
-- Beantwortet: Lässt die Applikation das (noch) zu? Wer muss handeln?
--
--   cases_last_4w / pct_last_4w : betroffene Vorgänge unter den in den letzten
--                                 4 Wochen gestarteten Vorgängen des Prozesses
--   status : 'neu'                    – erstmals in den letzten 8 Wochen aufgetreten
--            'tritt weiterhin auf'    – auch in den letzten 4 Wochen
--            'nicht mehr aufgetreten' – in den letzten 4 Wochen kein Vorkommen
-- Bezug: jüngster Vorgangsstart je Prozess (bei Live-Daten: current_timestamp()).
-- channels / first_release / system_status: über welchen Kanal, seit welchem Release,
-- und ob der Data Manager den Weg laut Status-Maschine erlaubt (oder er daran vorbei lief).
-- Parameter: :domain ('Alle' = kein Filter)
-- =====================================================================
WITH cases AS (
  SELECT process, case_id, case_start
  FROM main.data_manager_pm.v_case_conformance
  WHERE :domain = 'Alle' OR domain = :domain
),
ref AS (
  SELECT c.process, w.recent_from, w.new_from,
         COUNT(*) AS all_cases,
         COUNT_IF(c.case_start >= w.recent_from) AS recent_cases
  FROM cases c
  JOIN (SELECT process,
               MAX(case_start) - INTERVAL 28 DAYS AS recent_from,
               MAX(case_start) - INTERVAL 56 DAYS AS new_from
        FROM cases GROUP BY process) w USING (process)
  GROUP BY c.process, w.recent_from, w.new_from
),
f AS (
  SELECT f.*, c.case_start
  FROM main.data_manager_pm.v_findings f
  JOIN cases c USING (process, case_id)
)
SELECT
  f.process,
  f.finding_type,
  f.finding,
  f.severity,
  f.severity_rank,
  COUNT(DISTINCT f.case_id)                                                     AS cases,
  ROUND(COUNT(DISTINCT f.case_id) * 100.0 / r.all_cases, 1)                     AS pct_of_cases,
  COUNT(DISTINCT IF(f.case_start >= r.recent_from, f.case_id, NULL))            AS cases_last_4w,
  ROUND(COUNT(DISTINCT IF(f.case_start >= r.recent_from, f.case_id, NULL)) * 100.0 / r.recent_cases, 1) AS pct_last_4w,
  CAST(MIN(f.event_ts) AS DATE)                                                 AS first_seen,
  CAST(MAX(f.event_ts) AS DATE)                                                 AS last_seen,
  CASE
    WHEN MIN(f.case_start) >= r.new_from    THEN 'neu'
    WHEN MAX(f.case_start) >= r.recent_from THEN 'tritt weiterhin auf'
    ELSE 'nicht mehr aufgetreten'
  END                                                                           AS status,
  MAX(f.recommended_action)                                                     AS recommended_action,
  array_join(array_sort(collect_set(f.channel)), ', ')                          AS channels,
  MIN_BY(f.app_version, f.event_ts)                                             AS first_release,
  CASE WHEN BOOL_OR(f.system_status = 'außerhalb des Workflows') THEN 'außerhalb des Workflows'
       WHEN BOOL_OR(f.system_status = 'vom System erlaubt')      THEN 'vom System erlaubt'
       ELSE 'Regelprüfung' END                                                   AS system_status,
  MAX(pc.owner)                                                                 AS process_owner
FROM f
JOIN ref r USING (process)
JOIN main.data_manager_pm.process_catalog pc USING (process)
GROUP BY f.process, f.finding_type, f.finding, f.severity, f.severity_rank, r.recent_from, r.new_from, r.all_cases, r.recent_cases
ORDER BY f.severity_rank, cases_last_4w DESC, cases DESC;
