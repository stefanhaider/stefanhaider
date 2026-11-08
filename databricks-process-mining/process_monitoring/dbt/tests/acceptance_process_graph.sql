{{ config(enabled = var('use_sample_data') | as_bool, tags = ['acceptance']) }}
WITH g AS (SELECT * FROM {{ ref('mart_process_graph') }} WHERE domain_scope = 'Alle'),
checks AS (
  SELECT process AS pruefung, concat_ws(' / ', COUNT_IF(row_type = 'node'),
         concat_ws(', ', array_sort(collect_list(IF(row_type = 'arrow' AND conformance = 'latent', id, NULL))))) AS ist,
         CASE process WHEN 'Access Request' THEN '7 / Beantragt → Berechtigung erteilt'
                      WHEN 'Data Contract'  THEN '12 / '
                      ELSE '9 / Metadaten erfasst → Freigabe Data Owner' END AS soll
  FROM g GROUP BY process
  UNION ALL SELECT 'Scopes je Prozess', CAST(COUNT(DISTINCT process, domain_scope) AS STRING), '15' FROM {{ ref('mart_process_graph') }}
)
SELECT * FROM checks WHERE NOT (ist <=> soll)
