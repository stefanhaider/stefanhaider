-- =====================================================================
-- Zusammenfassung je unzulässigem Übergang: Lässt die Applikation diesen
-- Weg (noch) zu? Erstes/letztes Auftreten und betroffene Fälle unter den
-- in den letzten 4 Wochen gestarteten Fällen (Bezug: jüngster Fallstart).
-- Klassifizierung identisch zu 05_deviations_dataset.sql. Bei zusätzlichen
-- Aktivitäten wird nur der Übergang IN die Aktivität gelistet (nicht der
-- Weg heraus), damit jede Abweichung nur einmal erscheint.
-- Optionaler Dashboard-Parameter :region ('Alle' = kein Filter).
-- =====================================================================
WITH ev AS (
  SELECT * FROM main.process_mining.event_log
  WHERE :region = 'Alle' OR region = :region
),
starts AS (
  SELECT case_id, MIN(event_ts) AS case_start FROM ev GROUP BY case_id
),
seq AS (
  SELECT case_id, activity, event_ts,
         LAG(activity)  OVER w AS prev_activity,
         LEAD(activity) OVER w AS next_activity,
         LEAD(event_ts) OVER w AS next_ts
  FROM ev
  WINDOW w AS (PARTITION BY case_id ORDER BY event_ts, step_no)
),
trans AS (
  SELECT case_id, activity AS src, COALESCE(next_activity, '■ Ende') AS tgt, COALESCE(next_ts, event_ts) AS event_ts FROM seq
  UNION ALL
  SELECT case_id, '▶ Start', activity, event_ts FROM seq WHERE prev_activity IS NULL
),
dev AS (
  SELECT t.*, st.case_start,
    CASE
      WHEN ms.activity IS NULL OR mt.activity IS NULL THEN 'Zusätzliche Aktivität'
      WHEN t.tgt = '■ Ende'                           THEN 'Kein gültiger Abschluss'
      WHEN mt.is_terminal                             THEN 'Abbruch an unzulässiger Stelle'
      WHEN mt.step_order <= ms.step_order             THEN 'Rücksprung / Wiederholung'
      WHEN mt.step_order >  ms.step_order + 1         THEN 'Schritt übersprungen'
      ELSE 'Unzulässiger Übergang'
    END AS deviation_type
  FROM trans t
  LEFT JOIN main.process_mining.process_model_transitions m  ON m.src = t.src AND m.tgt = t.tgt
  LEFT JOIN main.process_mining.process_model_activities  ms ON ms.activity = t.src
  LEFT JOIN main.process_mining.process_model_activities  mt ON mt.activity = t.tgt
  JOIN starts st ON st.case_id = t.case_id
  WHERE m.src IS NULL
    AND NOT (ms.activity IS NULL AND mt.activity IS NOT NULL)   -- Weg aus Zusatz-Aktivität zurück: nicht doppelt zählen
),
ref AS (
  SELECT recent_from, COUNT(*) AS all_cases, COUNT_IF(case_start >= recent_from) AS recent_cases
  FROM starts CROSS JOIN (SELECT MAX(case_start) - INTERVAL 28 DAYS AS recent_from FROM starts)
  GROUP BY recent_from
)
SELECT
  d.deviation_type,
  concat(d.src, ' → ', d.tgt)                                    AS transition,
  COUNT(DISTINCT d.case_id)                                      AS cases,
  ROUND(COUNT(DISTINCT d.case_id) * 100.0 / r.all_cases, 1)      AS pct_of_cases,
  CAST(MIN(d.event_ts) AS DATE)                                  AS first_seen,
  CAST(MAX(d.event_ts) AS DATE)                                  AS last_seen,
  COUNT(DISTINCT IF(d.case_start >= r.recent_from, d.case_id, NULL))                       AS cases_last_4w,
  ROUND(COUNT(DISTINCT IF(d.case_start >= r.recent_from, d.case_id, NULL)) * 100.0 / r.recent_cases, 1) AS pct_last_4w,
  IF(MAX(d.case_start) >= r.recent_from, 'tritt weiterhin auf', 'in den letzten 4 Wochen nicht mehr') AS status
FROM dev d CROSS JOIN ref r
GROUP BY d.deviation_type, d.src, d.tgt, r.recent_from, r.all_cases, r.recent_cases
ORDER BY cases DESC;
