-- Data Contract: vom Data Manager abgewiesene Statuswechsel (Nachweis wirksamer Kontrollen).
SELECT
  r.process,
  r.case_id,
  r.domain,
  r.from_activity,
  r.attempted_activity,
  r.attempted_transition,
  r.actor,
  r.channel,
  r.app_version,
  r.event_ts,
  r.finding_type,
  r.attempt,
  pc.owner AS process_owner
FROM {{ ref('int_rejected_attempts') }} r
JOIN {{ ref('stg_dm__process_catalog') }} pc USING (process)
