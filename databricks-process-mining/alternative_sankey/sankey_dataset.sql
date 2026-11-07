-- =====================================================================
-- Dataset für das Sankey-Widget: ein Pfad (Variante) pro Zeile.
-- Jede Spalte step_1 … step_7 ist eine Sankey-Stufe, `cases` ist der Wert.
-- Gleiche Aktivitäten in verschiedenen Stufen sind eigene Knoten, deshalb
-- werden Schleifen (z. B. "Auftrag freigegeben" zweimal) sichtbar.
-- Kürzere Pfade enden mit NULL (der Fluss hört dort auf).
-- =====================================================================
WITH traces AS (
  SELECT
    case_id,
    region,
    transform(array_sort(collect_list(struct(event_ts, step_no, activity))), x -> x.activity) AS trace,
    timestampdiff(HOUR, min(event_ts), max(event_ts)) / 24.0 AS throughput_days
  FROM main.process_mining.event_log
  GROUP BY case_id, region
)
SELECT
  region,
  try_element_at(trace, 1) AS step_1,
  try_element_at(trace, 2) AS step_2,
  try_element_at(trace, 3) AS step_3,
  try_element_at(trace, 4) AS step_4,
  try_element_at(trace, 5) AS step_5,
  try_element_at(trace, 6) AS step_6,
  try_element_at(trace, 7) AS step_7,
  array_join(trace, ' → ')                 AS variant,
  COUNT(*)                                 AS cases,
  ROUND(AVG(throughput_days), 1)           AS avg_throughput_days
FROM traces
GROUP BY ALL;
