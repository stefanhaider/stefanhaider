-- =====================================================================
-- Dataset für die Übergangs-Heatmaps (Directly-Follows-Beziehungen)
-- Eine Zeile pro Übergang A → B innerhalb eines Falls, inkl. Wartezeit.
-- Die Widgets aggregieren: COUNT(*) = Häufigkeit, MEDIAN(wait_h) = Wartezeit.
-- "■ Ende" markiert die letzte Aktivität eines Falls (Prozessende/Abbruch).
-- =====================================================================
WITH t AS (
  SELECT
    case_id,
    region,
    activity AS from_activity,
    event_ts,
    LEAD(activity) OVER (PARTITION BY case_id ORDER BY event_ts, step_no) AS to_activity,
    LEAD(event_ts) OVER (PARTITION BY case_id ORDER BY event_ts, step_no) AS next_ts
  FROM main.process_mining.event_log
)
SELECT
  case_id,
  region,
  from_activity,
  COALESCE(to_activity, '■ Ende')               AS to_activity,
  timestampdiff(MINUTE, event_ts, next_ts) / 60.0 AS wait_h   -- NULL beim Ende
FROM t;
