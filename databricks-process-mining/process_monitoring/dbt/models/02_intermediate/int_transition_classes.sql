-- Aus dem getesteten Referenzstand (vormals View v_transition_classes).
WITH ev AS (
  SELECT process, case_id, activity, event_ts, step_no
  FROM {{ ref('int_event_log') }} WHERE event_type = 'transition'
),
seq AS (
  SELECT process, activity,
         LAG(activity) OVER w AS prev_activity, LEAD(activity) OVER w AS next_activity
  FROM ev WINDOW w AS (PARTITION BY process, case_id ORDER BY event_ts, step_no)
),
pairs AS (
  SELECT process, activity AS src, COALESCE(next_activity, '■ Ende') AS tgt FROM seq
  UNION SELECT process, '▶ Start', activity FROM seq WHERE prev_activity IS NULL
  UNION SELECT process, src, tgt FROM {{ ref('stg_dm__process_model_transition') }}
  UNION SELECT process, src, tgt FROM {{ ref('int_system_allowed_transitions') }}
  UNION SELECT process, from_activity, activity FROM {{ ref('int_event_log') }}
        WHERE event_type = 'rejected' AND from_activity IS NOT NULL
),
-- Kontrollschritte, die bei einem Sprung nach vorne übersprungen werden (in Soll-Reihenfolge)
skipped AS (
  SELECT p.process, p.src, p.tgt,
         array_join(transform(array_sort(collect_list(struct(c.step_order, c.activity))), x -> x.activity), ', ') AS skipped_controls
  FROM pairs p
  JOIN {{ ref('stg_dm__process_model_activity') }} ms ON ms.process = p.process AND ms.activity = p.src
  JOIN {{ ref('stg_dm__process_model_activity') }} mt ON mt.process = p.process AND mt.activity = p.tgt
  JOIN {{ ref('stg_dm__process_model_activity') }} c
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
LEFT JOIN {{ ref('stg_dm__process_model_transition') }} m
  ON m.process = p.process AND m.src = p.src AND m.tgt = p.tgt
LEFT JOIN {{ ref('stg_dm__process_model_activity') }} ms ON ms.process = p.process AND ms.activity = p.src
LEFT JOIN {{ ref('stg_dm__process_model_activity') }} mt ON mt.process = p.process AND mt.activity = p.tgt
LEFT JOIN skipped sk ON sk.process = p.process AND sk.src = p.src AND sk.tgt = p.tgt
