-- =====================================================================
-- Data Manager – Views mit der gesamten Auswertungslogik
--
--   v_transition_classes   jeder denkbare Übergang (Soll ∪ System ∪ Ist) mit Klassifizierung
--   v_transitions          jeder tatsächliche Übergang je Vorgang (Soll-, System- und Ist-Sicht)
--   v_rule_violations      Verstöße gegen Funktionstrennung (sod) und Fristen (sla)
--   v_findings             alle Befunde (Pfad + Regeln) je Vorgang, mit Schweregrad, Kanal, Release
--   v_case_conformance     ein Datensatz je Vorgang: konform?, kritische Befunde?, Liste
--   v_system_conformance   Soll vs. System vs. Ist je Übergang (System-Prozess-Konformität)
--   v_rejected_attempts    vom System abgewiesene Versuche (Nachweis wirksamer Kontrollen)
--
-- Die Dashboard-Datasets (04–10) lesen nur diese Views.
-- Nur Events mit event_type = 'transition' sind Statuswechsel; 'rejected' sind Versuche.
-- =====================================================================

CREATE OR REPLACE VIEW main.data_manager_pm.v_transition_classes AS
WITH ev AS (
  SELECT process, case_id, activity, event_ts, step_no
  FROM main.data_manager_pm.event_log WHERE event_type = 'transition'
),
seq AS (
  SELECT process, activity,
         LAG(activity) OVER w AS prev_activity, LEAD(activity) OVER w AS next_activity
  FROM ev WINDOW w AS (PARTITION BY process, case_id ORDER BY event_ts, step_no)
),
pairs AS (
  SELECT process, activity AS src, COALESCE(next_activity, '■ Ende') AS tgt FROM seq
  UNION SELECT process, '▶ Start', activity FROM seq WHERE prev_activity IS NULL
  UNION SELECT process, src, tgt FROM main.data_manager_pm.process_model_transitions
  UNION SELECT process, src, tgt FROM main.data_manager_pm.system_allowed_transitions
  UNION SELECT process, from_activity, activity FROM main.data_manager_pm.event_log
        WHERE event_type = 'rejected' AND from_activity IS NOT NULL
),
-- Kontrollschritte, die bei einem Sprung nach vorne übersprungen werden (in Soll-Reihenfolge)
skipped AS (
  SELECT p.process, p.src, p.tgt,
         array_join(transform(array_sort(collect_list(struct(c.step_order, c.activity))), x -> x.activity), ', ') AS skipped_controls
  FROM pairs p
  JOIN main.data_manager_pm.process_model_activities ms ON ms.process = p.process AND ms.activity = p.src
  JOIN main.data_manager_pm.process_model_activities mt ON mt.process = p.process AND mt.activity = p.tgt
  JOIN main.data_manager_pm.process_model_activities c
    ON c.process = p.process AND c.is_control AND c.step_order > ms.step_order AND c.step_order < mt.step_order
  GROUP BY p.process, p.src, p.tgt
)
SELECT
  p.process, p.src, p.tgt,
  m.src IS NOT NULL       AS is_allowed,
  ms.activity IS NOT NULL AS src_in_model,
  mt.activity IS NOT NULL AS tgt_in_model,
  sk.skipped_controls,
  CASE
    WHEN m.src IS NOT NULL                           THEN NULL
    WHEN ms.activity IS NULL OR mt.activity IS NULL  THEN 'Zusätzliche Aktivität'
    WHEN p.tgt = '■ Ende'                            THEN 'Kein gültiger Abschluss'
    WHEN mt.is_terminal                              THEN 'Abbruch an unzulässiger Stelle'
    WHEN mt.step_order <= ms.step_order              THEN 'Rücksprung / Wiederholung'
    WHEN sk.skipped_controls IS NOT NULL             THEN 'Kontrolle umgangen'
    WHEN mt.step_order > ms.step_order + 1           THEN 'Schritt übersprungen'
    ELSE 'Unzulässiger Übergang'
  END AS finding_type
FROM pairs p
LEFT JOIN main.data_manager_pm.process_model_transitions m
  ON m.process = p.process AND m.src = p.src AND m.tgt = p.tgt
LEFT JOIN main.data_manager_pm.process_model_activities ms ON ms.process = p.process AND ms.activity = p.src
LEFT JOIN main.data_manager_pm.process_model_activities mt ON mt.process = p.process AND mt.activity = p.tgt
LEFT JOIN skipped sk ON sk.process = p.process AND sk.src = p.src AND sk.tgt = p.tgt;


CREATE OR REPLACE VIEW main.data_manager_pm.v_transitions AS
WITH seq AS (
  SELECT
    process, case_id, domain, activity, actor, channel, app_version, event_ts,
    LAG(activity)     OVER w AS prev_activity,
    LEAD(activity)    OVER w AS next_activity,
    LEAD(event_ts)    OVER w AS next_ts,
    LEAD(actor)       OVER w AS next_actor,
    LEAD(channel)     OVER w AS next_channel,
    LEAD(app_version) OVER w AS next_app_version
  FROM main.data_manager_pm.event_log
  WHERE event_type = 'transition'
  WINDOW w AS (PARTITION BY process, case_id ORDER BY event_ts, step_no)
),
trans AS (
  SELECT process, case_id, domain, activity AS src, COALESCE(next_activity, '■ Ende') AS tgt,
         event_ts AS src_ts, COALESCE(next_ts, event_ts) AS tgt_ts,
         COALESCE(next_actor, actor) AS actor,
         COALESCE(next_channel, channel) AS channel,
         COALESCE(next_app_version, app_version) AS app_version
  FROM seq
  UNION ALL
  SELECT process, case_id, domain, '▶ Start', activity, event_ts, event_ts, actor, channel, app_version
  FROM seq WHERE prev_activity IS NULL
)
SELECT
  t.*,
  IF(t.src = '▶ Start' OR t.tgt = '■ Ende', NULL,
     (unix_timestamp(t.tgt_ts) - unix_timestamp(t.src_ts)) / 3600.0) AS wait_h,
  c.is_allowed, c.src_in_model, c.tgt_in_model, c.skipped_controls, c.finding_type,
  -- System-Sicht: war der Übergang zum Zeitpunkt laut Status-Maschine erlaubt?
  -- (Gültigkeitszeiträume je Übergang dürfen sich nicht überlappen)
  sa.src IS NOT NULL AS is_system_allowed
FROM trans t
JOIN main.data_manager_pm.v_transition_classes c
  ON c.process = t.process AND c.src = t.src AND c.tgt = t.tgt
LEFT JOIN main.data_manager_pm.system_allowed_transitions sa
  ON sa.process = t.process AND sa.src = t.src AND sa.tgt = t.tgt
 AND t.tgt_ts >= sa.valid_from AND (sa.valid_to IS NULL OR t.tgt_ts < sa.valid_to);


CREATE OR REPLACE VIEW main.data_manager_pm.v_rule_violations AS
WITH first_ev AS (   -- erstes Vorkommen je Aktivität und Vorgang, mit ausführender Person
  SELECT process, case_id, domain, activity, MIN(event_ts) AS ts,
         MIN_BY(actor, event_ts) AS actor, MIN_BY(channel, event_ts) AS channel,
         MIN_BY(app_version, event_ts) AS app_version
  FROM main.data_manager_pm.event_log
  WHERE event_type = 'transition'
  GROUP BY process, case_id, domain, activity
)
SELECT
  r.process, a.case_id, a.domain, r.rule_id, r.rule_type,
  CASE r.rule_type WHEN 'sod' THEN 'Funktionstrennung verletzt' ELSE 'Frist überschritten' END AS finding_type,
  CASE r.rule_type
    WHEN 'sod' THEN r.description
    ELSE concat(r.activity_a, ' → ', r.activity_b, ' über ', CAST(CAST(r.max_hours / 24 AS INT) AS STRING), ' Tage')
  END AS finding,
  b.ts AS event_ts, b.actor, b.channel, b.app_version,
  r.severity,
  ROUND((unix_timestamp(b.ts) - unix_timestamp(a.ts)) / 3600.0, 1) AS duration_h
FROM main.data_manager_pm.governance_rules r
JOIN first_ev a ON a.process = r.process AND a.activity = r.activity_a
JOIN first_ev b ON b.process = a.process AND b.case_id = a.case_id AND b.activity = r.activity_b
WHERE (r.rule_type = 'sod' AND a.actor = b.actor)
   OR (r.rule_type = 'sla' AND (unix_timestamp(b.ts) - unix_timestamp(a.ts)) / 3600.0 > r.max_hours);


CREATE OR REPLACE VIEW main.data_manager_pm.v_findings AS
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
FROM main.data_manager_pm.v_transitions t
JOIN main.data_manager_pm.finding_severity s ON s.finding_type = t.finding_type
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
FROM main.data_manager_pm.v_rule_violations v
JOIN main.data_manager_pm.finding_severity s ON s.finding_type = v.finding_type;


CREATE OR REPLACE VIEW main.data_manager_pm.v_case_conformance AS
WITH path AS (
  SELECT process, case_id, domain,
         BOOL_AND(is_allowed) AS path_ok,
         BOOL_OR(NOT is_system_allowed) AS outside_workflow
  FROM main.data_manager_pm.v_transitions GROUP BY process, case_id, domain
),
ev AS (
  SELECT process, case_id, MIN(event_ts) AS case_start, MAX(event_ts) AS case_end,
         MIN_BY(actor, event_ts) AS initiator, MIN_BY(channel, event_ts) AS start_channel
  FROM main.data_manager_pm.event_log WHERE event_type = 'transition' GROUP BY process, case_id
),
f AS (
  SELECT process, case_id,
         COUNT(*)                                                   AS n_findings,
         MAX(IF(severity = 'kritisch', 1, 0))                       AS has_critical,
         MAX(IF(finding_type = 'Kontrolle umgangen', 1, 0))         AS has_control_bypass,
         MAX(IF(finding_type = 'Funktionstrennung verletzt', 1, 0)) AS has_sod_violation,
         MAX(IF(finding_type = 'Frist überschritten', 1, 0))        AS has_sla_breach,
         array_join(array_sort(collect_set(finding)), ' | ')        AS findings
  FROM main.data_manager_pm.v_findings GROUP BY process, case_id
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
LEFT JOIN f USING (process, case_id);


CREATE OR REPLACE VIEW main.data_manager_pm.v_system_conformance AS
WITH sys AS (
  SELECT process, src, tgt,
         BOOL_OR(valid_to IS NULL)                                   AS in_system,
         BOOL_OR(valid_to IS NOT NULL)                               AS was_in_system,
         MAX_BY(note, valid_from)                                    AS system_note,
         MAX_BY(since_release, valid_from)                           AS since_release,
         MAX(valid_to)                                               AS removed_at
  FROM main.data_manager_pm.system_allowed_transitions
  GROUP BY process, src, tgt
),
obs AS (
  SELECT process, src, tgt,
         COUNT(DISTINCT case_id)                                     AS observed_cases,
         COUNT(DISTINCT IF(NOT is_system_allowed, case_id, NULL))    AS cases_outside_workflow,
         array_join(array_sort(collect_set(channel)), ', ')          AS channels,
         CAST(MIN(tgt_ts) AS DATE)                                   AS first_seen,
         CAST(MAX(tgt_ts) AS DATE)                                   AS last_seen
  FROM main.data_manager_pm.v_transitions
  GROUP BY process, src, tgt
),
rej AS (
  SELECT process, from_activity AS src, activity AS tgt, COUNT(*) AS rejected_attempts
  FROM main.data_manager_pm.event_log WHERE event_type = 'rejected'
  GROUP BY process, from_activity, activity
)
SELECT
  c.process, c.src, c.tgt, concat(c.src, ' → ', c.tgt) AS transition,
  c.is_allowed                     AS in_soll,
  COALESCE(s.in_system, false)     AS in_system,
  COALESCE(o.observed_cases, 0)    AS observed_cases,
  COALESCE(o.cases_outside_workflow, 0) AS cases_outside_workflow,
  COALESCE(r.rejected_attempts, 0) AS rejected_attempts,
  o.channels, o.first_seen, o.last_seen,
  s.system_note, s.since_release, s.removed_at,
  c.finding_type, c.skipped_controls,
  CASE
    WHEN COALESCE(o.cases_outside_workflow, 0) > 0                         THEN 'Umgehung außerhalb des Workflows'
    WHEN c.is_allowed AND NOT COALESCE(s.in_system, false)                 THEN 'Soll-Schritt nicht implementiert'
    WHEN NOT c.is_allowed AND s.in_system AND COALESCE(o.observed_cases, 0) > 0 THEN 'System lässt mehr zu – genutzt'
    WHEN NOT c.is_allowed AND s.in_system                                  THEN 'System lässt mehr zu – latent'
    WHEN NOT c.is_allowed AND s.was_in_system                              THEN 'Nicht mehr erlaubt'
    WHEN NOT c.is_allowed AND COALESCE(r.rejected_attempts, 0) > 0         THEN 'Vom System abgewiesen'
    ELSE 'Konform'
  END AS system_category,
  CASE
    WHEN COALESCE(o.cases_outside_workflow, 0) > 0                         THEN 'kritisch'
    WHEN c.is_allowed AND NOT COALESCE(s.in_system, false)                 THEN 'hoch'
    WHEN NOT c.is_allowed AND s.in_system AND COALESCE(o.observed_cases, 0) > 0
      THEN IF(c.finding_type = 'Kontrolle umgangen', 'kritisch', 'mittel')
    WHEN NOT c.is_allowed AND s.in_system
      THEN IF(c.finding_type = 'Kontrolle umgangen', 'hoch', 'mittel')
    ELSE NULL
  END AS severity
FROM main.data_manager_pm.v_transition_classes c
LEFT JOIN sys s USING (process, src, tgt)
LEFT JOIN obs o USING (process, src, tgt)
LEFT JOIN rej r USING (process, src, tgt);


CREATE OR REPLACE VIEW main.data_manager_pm.v_rejected_attempts AS
SELECT
  e.process, e.case_id, e.domain, e.from_activity, e.activity AS attempted_activity,
  concat(e.from_activity, ' → ', e.activity) AS attempted_transition,
  e.actor, e.channel, e.app_version, e.event_ts,
  c.finding_type,
  CASE WHEN c.finding_type = 'Kontrolle umgangen' THEN concat('Versuch: ', c.skipped_controls, ' umgehen')
       ELSE concat('Versuch: ', e.from_activity, ' → ', e.activity) END AS attempt
FROM main.data_manager_pm.event_log e
LEFT JOIN main.data_manager_pm.v_transition_classes c
  ON c.process = e.process AND c.src = e.from_activity AND c.tgt = e.activity
WHERE e.event_type = 'rejected';
