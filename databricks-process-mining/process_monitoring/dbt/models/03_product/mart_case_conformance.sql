-- Data Contract: ein Datensatz je Vorgang (alle Prozesse) – KPIs, Trends, Drill-down.
SELECT
  c.process,
  c.case_id,
  c.domain,
  c.initiator,
  c.start_channel,
  c.case_start,
  CAST(c.throughput_days AS DECIMAL(10, 2)) AS throughput_days,
  c.is_conformant,
  c.is_compliant,
  c.has_outside_workflow,
  CAST(c.n_findings AS INT)                 AS n_findings,
  c.has_critical,
  c.has_control_bypass,
  c.has_sod_violation,
  c.has_sla_breach,
  c.findings,
  pc.owner                                  AS process_owner
FROM {{ ref('int_case_conformance') }} c
JOIN {{ ref('stg_dm__process_catalog') }} pc USING (process)
