-- Governance-Regeln (Funktionstrennung, Fristen) der aktuell freigegebenen Modell-Version
SELECT r.process, r.rule_id, r.rule_type, r.activity_a, r.activity_b, CAST(r.max_hours AS INT) AS max_hours,
       r.description, r.severity, r.model_version
FROM {{ dm_source('governance_rule') }} r
JOIN {{ dm_source('process_model_version') }} v ON v.model_version = r.model_version AND v.is_current
