{{ config(enabled = var('use_sample_data') | as_bool, tags = ['acceptance']) }}
WITH s AS (SELECT * FROM {{ ref('mart_system_conformance') }}),
cat AS (
  SELECT system_category, concat_ws(' | ', array_sort(collect_list(concat(process, ': ', transition)))) AS items, COUNT(*) AS n
  FROM s GROUP BY system_category
),
checks AS (
  SELECT 'gesamt/konform/system/soll' AS pruefung,
         concat_ws('/', COUNT(*), COUNT_IF(system_category = 'Konform'), COUNT_IF(in_system), COUNT_IF(in_soll)) AS ist,
         '42/31/38/32' AS soll FROM s
  UNION ALL SELECT 'außerhalb', items, 'Access Request: ▶ Start → Berechtigung erteilt | Data Product: Angelegt → Veröffentlicht'
            FROM cat WHERE system_category = 'Umgehung außerhalb des Workflows'
  UNION ALL SELECT 'latent', items, 'Access Request: Beantragt → Berechtigung erteilt | Data Product: Metadaten erfasst → Freigabe Data Owner'
            FROM cat WHERE system_category = 'System lässt mehr zu – latent'
  UNION ALL SELECT 'nicht implementiert', items, 'Data Contract: Review Änderung → Verworfen'
            FROM cat WHERE system_category = 'Soll-Schritt nicht implementiert'
  UNION ALL SELECT 'genutzt', CAST(n AS STRING), '5' FROM cat WHERE system_category = 'System lässt mehr zu – genutzt'
  UNION ALL SELECT 'abgewiesene Versuche', CAST(COUNT(*) AS STRING), '25' FROM {{ ref('mart_rejected_attempts') }}
  UNION ALL SELECT 'Alarm Zeilen/neu', concat_ws('/', COUNT(*), COUNT_IF(is_new)), '5/1' FROM {{ ref('mart_alert_critical_findings') }}
)
SELECT * FROM checks WHERE NOT (ist <=> soll)
