-- =====================================================================
-- Alle unzulässigen Übergänge (eine Zeile je Vorkommen) mit Abweichungstyp.
-- Basis für "Fälle je Abweichungstyp" und Drill-down auf einzelne Fälle.
--
-- Abweichungstypen (Reihenfolge laut process_model_activities.step_order):
--   Zusätzliche Aktivität        : Aktivität ist nicht Teil des Soll-Prozesses
--   Schritt übersprungen         : Sprung nach vorne über mind. einen Soll-Schritt
--   Rücksprung / Wiederholung    : zurück zu einem früheren oder gleichen Schritt
--   Abbruch an unzulässiger Stelle: Terminal-Aktivität (z. B. Storno) von hier nicht erlaubt
--   Kein gültiger Abschluss      : Fall endet nach einer Nicht-End-Aktivität
-- =====================================================================
WITH seq AS (
  SELECT
    case_id, region, activity, event_ts,
    LAG(activity)  OVER w AS prev_activity,
    LEAD(activity) OVER w AS next_activity,
    LEAD(event_ts) OVER w AS next_ts
  FROM main.process_mining.event_log
  WINDOW w AS (PARTITION BY case_id ORDER BY event_ts, step_no)
),
trans AS (
  SELECT case_id, region, activity AS src, COALESCE(next_activity, '■ Ende') AS tgt,
         COALESCE(next_ts, event_ts) AS event_ts FROM seq
  UNION ALL
  SELECT case_id, region, '▶ Start', activity, event_ts FROM seq WHERE prev_activity IS NULL
)
SELECT
  t.case_id,
  t.region,
  t.src,
  t.tgt,
  concat(t.src, ' → ', t.tgt) AS transition,
  t.event_ts,
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
WHERE m.src IS NULL;
