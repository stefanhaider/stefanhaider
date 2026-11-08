{{ config(enabled = var('use_sample_data') | as_bool, tags = ['acceptance']) }}
-- Abnahmewerte mit Beispieldaten (IMPLEMENTATION_SPEC.md, Abschnitt 10). Liefert Zeilen = Abweichung.
WITH a AS (
  SELECT process, COUNT(*) AS n, ROUND(AVG(is_conformant) * 100, 1) AS rate, ROUND(AVG(is_compliant) * 100, 1) AS comp,
         SUM(has_critical) AS crit, SUM(has_control_bypass) AS bypass, SUM(has_sod_violation) AS sod, SUM(has_sla_breach) AS sla
  FROM {{ ref('mart_case_conformance') }} GROUP BY process
  UNION ALL
  SELECT 'GESAMT', COUNT(*), ROUND(AVG(is_conformant) * 100, 1), ROUND(AVG(is_compliant) * 100, 1),
         SUM(has_critical), SUM(has_control_bypass), SUM(has_sod_violation), SUM(has_sla_breach)
  FROM {{ ref('mart_case_conformance') }}
),
e AS (
  SELECT * FROM VALUES
    ('Access Request', 500, 72.0, 63.6, 123, 105, 23, 42),
    ('Data Contract',  300, 78.3, 74.3,  73,  65, 10,  6),
    ('Data Product',   200, 75.0, 72.0,  55,  50,  6,  1),
    ('GESAMT',        1000, 74.5, 68.5, 251, 220, 39, 49)
  AS e(process, n, rate, comp, crit, bypass, sod, sla)
)
SELECT e.*, a.n AS a_n, a.rate AS a_rate, a.comp AS a_comp, a.crit AS a_crit
FROM e FULL OUTER JOIN a ON a.process = e.process
WHERE NOT (a.n <=> e.n AND a.rate <=> e.rate AND a.comp <=> e.comp AND a.crit <=> e.crit
           AND a.bypass <=> e.bypass AND a.sod <=> e.sod AND a.sla <=> e.sla)
