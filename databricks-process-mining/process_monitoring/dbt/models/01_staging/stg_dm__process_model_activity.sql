-- Soll-Aktivitäten der aktuell freigegebenen Modell-Version
SELECT a.process, a.activity, CAST(a.step_order AS INT) AS step_order, a.is_terminal, a.is_control, a.model_version
FROM {{ dm_source('process_model_activity') }} a
JOIN {{ dm_source('process_model_version') }} v ON v.model_version = a.model_version AND v.is_current
