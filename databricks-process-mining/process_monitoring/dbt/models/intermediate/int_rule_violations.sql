-- Aus dem getesteten Referenzstand (vormals View v_rule_violations).
WITH first_ev AS (   -- erstes Vorkommen je Aktivität und Vorgang, mit ausführender Person
  SELECT process, case_id, domain, activity, MIN(event_ts) AS ts,
         MIN_BY(actor, event_ts) AS actor, MIN_BY(channel, event_ts) AS channel,
         MIN_BY(app_version, event_ts) AS app_version
  FROM {{ ref('int_event_log') }}
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
FROM {{ ref('stg_dm__governance_rule') }} r
JOIN first_ev a ON a.process = r.process AND a.activity = r.activity_a
JOIN first_ev b ON b.process = a.process AND b.case_id = a.case_id AND b.activity = r.activity_b
WHERE (r.rule_type = 'sod' AND a.actor = b.actor)
   OR (r.rule_type = 'sla' AND (unix_timestamp(b.ts) - unix_timestamp(a.ts)) / 3600.0 > r.max_hours)
