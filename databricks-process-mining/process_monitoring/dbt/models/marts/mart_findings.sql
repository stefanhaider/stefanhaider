-- Jedes einzelne Befund-Vorkommen (Pfad-Abweichungen und Regelverstöße) – Drill-down, Audit-Export.
SELECT f.*, pc.owner AS process_owner
FROM {{ ref('int_findings') }} f
JOIN {{ ref('stg_dm__process_catalog') }} pc USING (process)
