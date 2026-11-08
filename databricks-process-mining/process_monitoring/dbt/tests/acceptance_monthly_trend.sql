{{ config(enabled = var('use_sample_data') | as_bool, tags = ['acceptance']) }}
-- Access Request: Konformität Jan 90,0 % -> Apr 60,6 % -> Jun 58,9 % (Freigabe ohne Security-Prüfung ab KW 14)
WITH a AS (
  SELECT date_format(date_trunc('MONTH', case_start), 'yyyy-MM') AS m, ROUND(AVG(is_conformant) * 100, 1) AS rate
  FROM {{ ref('mart_case_conformance') }} WHERE process = 'Access Request' GROUP BY 1
),
e AS (SELECT * FROM VALUES ('2026-01', 90.0), ('2026-04', 60.6), ('2026-06', 58.9) AS e(m, rate))
SELECT e.*, a.rate AS actual FROM e LEFT JOIN a USING (m) WHERE NOT (a.rate <=> e.rate)
