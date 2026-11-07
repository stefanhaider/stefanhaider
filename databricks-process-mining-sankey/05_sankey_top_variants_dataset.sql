-- =====================================================================
-- Sankey nur für die Top-5-Varianten, Rest wird zu "Sonstige Varianten"
-- zusammengefasst. Hält das Sankey auch bei hunderten Varianten lesbar.
-- =====================================================================
WITH traces AS (
  SELECT
    case_id,
    region,
    transform(array_sort(collect_list(struct(event_ts, step_no, activity))), x -> x.activity) AS trace
  FROM main.process_mining.event_log
  GROUP BY case_id, region
),
ranked AS (
  SELECT *, DENSE_RANK() OVER (ORDER BY variant_cases DESC, variant) AS variant_rank
  FROM (SELECT *, COUNT(*) OVER (PARTITION BY trace) AS variant_cases,
               array_join(trace, ' → ') AS variant
        FROM traces)
)
SELECT
  region,
  variant_rank,
  IF(variant_rank <= 5, variant, 'Sonstige Varianten') AS variant,
  try_element_at(trace, 1)                                         AS step_1,
  IF(variant_rank <= 5, try_element_at(trace, 2), 'Sonstige Varianten') AS step_2,
  IF(variant_rank <= 5, try_element_at(trace, 3), NULL)            AS step_3,
  IF(variant_rank <= 5, try_element_at(trace, 4), NULL)            AS step_4,
  IF(variant_rank <= 5, try_element_at(trace, 5), NULL)            AS step_5,
  IF(variant_rank <= 5, try_element_at(trace, 6), NULL)            AS step_6,
  IF(variant_rank <= 5, try_element_at(trace, 7), NULL)            AS step_7,
  COUNT(*)                                                         AS cases
FROM ranked
GROUP BY ALL;
