-- Data Contract: Soll-Prozess vs. Status-Maschine vs. Ist je Übergang (System-Prozess-Konformität).
SELECT
  v.process,
  v.src,
  v.tgt,
  v.transition,
  v.in_soll,
  v.in_system,
  v.observed_cases,
  v.cases_outside_workflow,
  v.rejected_attempts,
  v.channels,
  v.first_seen,
  v.last_seen,
  v.system_note,
  v.since_release,
  v.removed_at,
  v.finding_type,
  v.skipped_controls,
  v.system_category,
  v.severity,
  CASE v.severity WHEN 'kritisch' THEN 1 WHEN 'hoch' THEN 2 WHEN 'mittel' THEN 3 ELSE 4 END AS severity_rank,
  pc.owner AS process_owner
FROM {{ ref('int_system_conformance') }} v
JOIN {{ ref('stg_dm__process_catalog') }} pc USING (process)
