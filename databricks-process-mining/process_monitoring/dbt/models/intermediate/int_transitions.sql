-- Aus dem getesteten Referenzstand (vormals View v_transitions).
WITH seq AS (
  SELECT
    process, case_id, domain, activity, actor, channel, app_version, event_ts,
    LAG(activity)     OVER w AS prev_activity,
    LEAD(activity)    OVER w AS next_activity,
    LEAD(event_ts)    OVER w AS next_ts,
    LEAD(actor)       OVER w AS next_actor,
    LEAD(channel)     OVER w AS next_channel,
    LEAD(app_version) OVER w AS next_app_version
  FROM {{ ref('int_event_log') }}
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
JOIN {{ ref('int_transition_classes') }} c
  ON c.process = t.process AND c.src = t.src AND c.tgt = t.tgt
LEFT JOIN {{ ref('int_system_allowed_transitions') }} sa
  ON sa.process = t.process AND sa.src = t.src AND sa.tgt = t.tgt
 AND t.tgt_ts >= sa.valid_from AND (sa.valid_to IS NULL OR t.tgt_ts < sa.valid_to)
