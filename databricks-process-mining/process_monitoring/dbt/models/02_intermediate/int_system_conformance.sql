-- Aus dem getesteten Referenzstand (vormals View v_system_conformance).
WITH sys AS (
  SELECT process, src, tgt,
         BOOL_OR(valid_to IS NULL)                                   AS in_system,
         BOOL_OR(valid_to IS NOT NULL)                               AS was_in_system,
         MAX_BY(note, valid_from)                                    AS system_note,
         MAX_BY(since_release, valid_from)                           AS since_release,
         MAX(valid_to)                                               AS removed_at
  FROM {{ ref('int_system_allowed_transitions') }}
  GROUP BY process, src, tgt
),
obs AS (
  SELECT process, src, tgt,
         COUNT(DISTINCT case_id)                                     AS observed_cases,
         COUNT(DISTINCT IF(NOT is_system_allowed, case_id, NULL))    AS cases_outside_workflow,
         array_join(array_sort(collect_set(channel)), ', ')          AS channels,
         CAST(MIN(tgt_ts) AS DATE)                                   AS first_seen,
         CAST(MAX(tgt_ts) AS DATE)                                   AS last_seen
  FROM {{ ref('int_transitions') }}
  GROUP BY process, src, tgt
),
rej AS (
  SELECT process, from_activity AS src, activity AS tgt, COUNT(*) AS rejected_attempts
  FROM {{ ref('int_event_log') }} WHERE event_type = 'rejected'
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
FROM {{ ref('int_transition_classes') }} c
LEFT JOIN sys s USING (process, src, tgt)
LEFT JOIN obs o USING (process, src, tgt)
LEFT JOIN rej r USING (process, src, tgt)
