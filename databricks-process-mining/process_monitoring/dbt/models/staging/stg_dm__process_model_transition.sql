-- Erlaubte Soll-Übergänge der aktuell freigegebenen Modell-Version
SELECT t.process, t.src, t.tgt, t.model_version
FROM {{ dm_source('process_model_transition') }} t
JOIN {{ dm_source('process_model_version') }} v ON v.model_version = t.model_version AND v.is_current
