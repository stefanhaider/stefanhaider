-- Aus dem getesteten Referenzstand (vormals View v_case_conformance).
WITH path AS (
  SELECT process, case_id, domain,
         BOOL_AND(is_allowed) AS path_ok,
         BOOL_OR(NOT is_system_allowed) AS outside_workflow
  FROM {{ ref('int_transitions') }} GROUP BY process, case_id, domain
),
ev AS (
  SELECT process, case_id, MIN(event_ts) AS case_start, MAX(event_ts) AS case_end,
         MIN_BY(actor, event_ts) AS initiator, MIN_BY(channel, event_ts) AS start_channel
  FROM {{ ref('int_event_log') }} WHERE event_type = 'transition' GROUP BY process, case_id
),
f AS (
  SELECT process, case_id,
         COUNT(*)                                                   AS n_findings,
         MAX(IF(severity = 'kritisch', 1, 0))                       AS has_critical,
         MAX(IF(finding_type = 'Kontrolle umgangen', 1, 0))         AS has_control_bypass,
         MAX(IF(finding_type = 'Funktionstrennung verletzt', 1, 0)) AS has_sod_violation,
         MAX(IF(finding_type = 'Frist überschritten', 1, 0))        AS has_sla_breach,
         array_join(array_sort(collect_set(finding)), ' | ')        AS findings
  FROM {{ ref('int_findings') }} GROUP BY process, case_id
)
SELECT
  p.process, p.case_id, p.domain, ev.initiator, ev.start_channel, ev.case_start,
  ROUND((unix_timestamp(ev.case_end) - unix_timestamp(ev.case_start)) / 86400.0, 2) AS throughput_days,
  CAST(p.path_ok AS INT)                       AS is_conformant,        -- Pfad laut Soll-Prozess
  CAST(p.path_ok AND f.case_id IS NULL AS INT) AS is_compliant,         -- zusätzlich keine Regelverstöße
  CAST(p.outside_workflow AS INT)              AS has_outside_workflow, -- mind. ein Übergang am Workflow vorbei
  COALESCE(f.n_findings, 0)           AS n_findings,
  COALESCE(f.has_critical, 0)         AS has_critical,
  COALESCE(f.has_control_bypass, 0)   AS has_control_bypass,
  COALESCE(f.has_sod_violation, 0)    AS has_sod_violation,
  COALESCE(f.has_sla_breach, 0)       AS has_sla_breach,
  COALESCE(f.findings, '')            AS findings
FROM path p
JOIN ev USING (process, case_id)
LEFT JOIN f USING (process, case_id)
