-- Data Contract: jedes Befund-Vorkommen (Pfad-Abweichungen und Regelverstöße) – Drill-down, Audit-Export.
SELECT
  f.process,
  f.case_id,
  f.domain,
  f.finding_type,
  f.finding,
  f.transition,
  f.event_ts,
  f.actor,
  f.channel,
  f.app_version,
  f.system_status,
  f.severity,
  CAST(f.severity_rank AS INT) AS severity_rank,
  f.recommended_action,
  f.source,
  pc.owner                     AS process_owner
FROM {{ ref('int_findings') }} f
JOIN {{ ref('stg_dm__process_catalog') }} pc USING (process)
