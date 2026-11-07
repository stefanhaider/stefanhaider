-- =====================================================================
-- Konformität je Fall: ein Fall ist konform, wenn ALLE seine direkten
-- Übergänge (inkl. Start → erste Aktivität und letzte Aktivität → Ende)
-- im Soll-Prozess erlaubt sind.
-- Basis für KPIs und den Trend der Konformitätsrate.
-- =====================================================================
WITH seq AS (
  SELECT
    case_id, region, activity, event_ts,
    LAG(activity)  OVER w AS prev_activity,
    LEAD(activity) OVER w AS next_activity
  FROM main.process_mining.event_log
  WINDOW w AS (PARTITION BY case_id ORDER BY event_ts, step_no)
),
trans AS (
  SELECT case_id, region, activity AS src, COALESCE(next_activity, '■ Ende') AS tgt, event_ts FROM seq
  UNION ALL
  SELECT case_id, region, '▶ Start', activity, event_ts FROM seq WHERE prev_activity IS NULL
),
checked AS (
  SELECT t.*, m.src IS NOT NULL AS is_allowed
  FROM trans t
  LEFT JOIN main.process_mining.process_model_transitions m ON m.src = t.src AND m.tgt = t.tgt
)
SELECT
  case_id,
  region,
  MIN(event_ts)                                                   AS case_start,
  timestampdiff(HOUR, MIN(event_ts), MAX(event_ts)) / 24.0        AS throughput_days,
  CAST(BOOL_AND(is_allowed) AS INT)                               AS is_conformant,
  COUNT_IF(NOT is_allowed)                                        AS n_deviating_transitions,
  array_join(array_sort(collect_set(IF(NOT is_allowed, concat(src, ' → ', tgt), NULL))), ' | ') AS deviations
FROM checked
GROUP BY case_id, region;
