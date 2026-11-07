-- KPI-Dataset für die Zähler-Kacheln oberhalb des Sankey-Diagramms
WITH traces AS (
  SELECT
    case_id, region,
    min(event_ts) AS case_start,
    array_join(transform(array_sort(collect_list(struct(event_ts, step_no, activity))), x -> x.activity), '|') AS variant,
    timestampdiff(HOUR, min(event_ts), max(event_ts)) / 24.0 AS throughput_days,
    max(CASE WHEN activity = 'Storniert' THEN 1 ELSE 0 END) AS is_cancelled,
    max(CASE WHEN activity IN ('Mahnung','Preisänderung','Gutschrift') THEN 1 ELSE 0 END) AS has_rework
  FROM main.process_mining.event_log
  GROUP BY case_id, region
)
SELECT region, case_id, case_start, variant, throughput_days, is_cancelled, has_rework
FROM traces;
