-- Aus dem getesteten Referenzstand (vormals View v_rejected_attempts).
SELECT
  e.process, e.case_id, e.domain, e.from_activity, e.activity AS attempted_activity,
  concat(e.from_activity, ' → ', e.activity) AS attempted_transition,
  e.actor, e.channel, e.app_version, e.event_ts,
  c.finding_type,
  CASE WHEN c.finding_type = 'Kontrolle umgangen' THEN concat('Versuch: ', c.skipped_controls, ' umgehen')
       ELSE concat('Versuch: ', e.from_activity, ' → ', e.activity) END AS attempt
FROM {{ ref('int_event_log') }} e
LEFT JOIN {{ ref('int_transition_classes') }} c
  ON c.process = e.process AND c.src = e.from_activity AND c.tgt = e.activity
WHERE e.event_type = 'rejected'
