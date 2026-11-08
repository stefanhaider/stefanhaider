-- Data Contract: ein Datensatz je Befund, Prozess und domain_scope ('Alle' oder eine Domäne).
-- Beantwortet: Lässt die Applikation das (noch) zu? Wer muss handeln?
--   cases_last_4w / pct_last_4w : betroffene unter den in den letzten recent_days gestarteten Vorgängen
--   status : 'neu' (erstes Auftreten in den letzten new_days) | 'tritt weiterhin auf' | 'nicht mehr aufgetreten'
-- Bezug: jüngster Vorgangsstart je Prozess und Scope.
WITH cases AS (
  SELECT process, case_id, domain, case_start FROM {{ ref('int_case_conformance') }}
),
scopes AS (SELECT DISTINCT domain AS domain_scope FROM cases UNION ALL SELECT 'Alle'),
scoped AS (
  SELECT s.domain_scope, c.* FROM cases c JOIN scopes s ON s.domain_scope = 'Alle' OR c.domain = s.domain_scope
),
ref_ts AS (
  SELECT c.process, c.domain_scope, w.recent_from, w.new_from,
         COUNT(*) AS all_cases, COUNT_IF(c.case_start >= w.recent_from) AS recent_cases
  FROM scoped c
  JOIN (SELECT process, domain_scope,
               MAX(case_start) - INTERVAL {{ var('recent_days') }} DAYS AS recent_from,
               MAX(case_start) - INTERVAL {{ var('new_days') }} DAYS AS new_from
        FROM scoped GROUP BY process, domain_scope) w USING (process, domain_scope)
  GROUP BY c.process, c.domain_scope, w.recent_from, w.new_from
),
f AS (
  SELECT c.domain_scope, f.*, c.case_start
  FROM {{ ref('int_findings') }} f
  JOIN scoped c ON c.process = f.process AND c.case_id = f.case_id
)
SELECT
  f.process, f.domain_scope, f.finding_type, f.finding, f.severity, f.severity_rank,
  COUNT(DISTINCT f.case_id)                                                       AS cases,
  CAST(ROUND(COUNT(DISTINCT f.case_id) * 100.0 / r.all_cases, 1) AS DECIMAL(5, 1)) AS pct_of_cases,
  COUNT(DISTINCT IF(f.case_start >= r.recent_from, f.case_id, NULL))              AS cases_last_4w,
  CAST(ROUND(COUNT(DISTINCT IF(f.case_start >= r.recent_from, f.case_id, NULL)) * 100.0 / r.recent_cases, 1) AS DECIMAL(5, 1)) AS pct_last_4w,
  CAST(MIN(f.event_ts) AS DATE)                                                   AS first_seen,
  CAST(MAX(f.event_ts) AS DATE)                                                   AS last_seen,
  CASE
    WHEN MIN(f.case_start) >= r.new_from    THEN 'neu'
    WHEN MAX(f.case_start) >= r.recent_from THEN 'tritt weiterhin auf'
    ELSE 'nicht mehr aufgetreten'
  END                                                                             AS status,
  MAX(f.recommended_action)                                                       AS recommended_action,
  array_join(array_sort(collect_set(f.channel)), ', ')                            AS channels,
  MIN_BY(f.app_version, f.event_ts)                                               AS first_release,
  CASE WHEN BOOL_OR(f.system_status = 'außerhalb des Workflows') THEN 'außerhalb des Workflows'
       WHEN BOOL_OR(f.system_status = 'vom System erlaubt')      THEN 'vom System erlaubt'
       ELSE 'Regelprüfung' END                                                     AS system_status,
  MAX(pc.owner)                                                                   AS process_owner
FROM f
JOIN ref_ts r ON r.process = f.process AND r.domain_scope = f.domain_scope
JOIN {{ ref('stg_dm__process_catalog') }} pc ON pc.process = f.process
GROUP BY f.process, f.domain_scope, f.finding_type, f.finding, f.severity, f.severity_rank,
         r.recent_from, r.new_from, r.all_cases, r.recent_cases
