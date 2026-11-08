-- Aus dem getesteten Referenzstand (vormals View v_findings).
SELECT
  t.process, t.case_id, t.domain, t.finding_type,
  CASE t.finding_type
    WHEN 'Kontrolle umgangen'        THEN concat(t.skipped_controls, ' umgangen')
    WHEN 'Zusätzliche Aktivität'     THEN concat('Zusätzlicher Schritt: ', IF(t.tgt_in_model, t.src, t.tgt))
    WHEN 'Rücksprung / Wiederholung' THEN concat('Rücksprung: ', t.src, ' → ', t.tgt)
    ELSE concat(t.src, ' → ', t.tgt)
  END AS finding,
  concat(t.src, ' → ', t.tgt) AS transition,
  t.tgt_ts AS event_ts,
  t.actor, t.channel, t.app_version,
  IF(t.is_system_allowed, 'vom System erlaubt', 'außerhalb des Workflows') AS system_status,
  s.severity, s.severity_rank, s.recommended_action,
  'Prozesspfad' AS source
FROM {{ ref('int_transitions') }} t
JOIN {{ ref('finding_severity') }} s ON s.finding_type = t.finding_type
WHERE t.finding_type IS NOT NULL
  AND NOT (NOT t.src_in_model AND t.tgt_in_model)   -- Rückweg aus einer Zusatz-Aktivität nicht doppelt zählen
UNION ALL
SELECT
  v.process, v.case_id, v.domain, v.finding_type, v.finding,
  CAST(NULL AS STRING), v.event_ts, v.actor, v.channel, v.app_version,
  CAST(NULL AS STRING),
  v.severity,
  CASE v.severity WHEN 'kritisch' THEN 1 WHEN 'hoch' THEN 2 ELSE 3 END,
  s.recommended_action,
  concat('Regel ', v.rule_id)
FROM {{ ref('int_rule_violations') }} v
JOIN {{ ref('finding_severity') }} s ON s.finding_type = v.finding_type
