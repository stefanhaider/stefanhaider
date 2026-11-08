-- Ein Datensatz je Vorgang (alle Prozesse): KPIs, Trends, Drill-down.
SELECT c.*, pc.owner AS process_owner
FROM {{ ref('int_case_conformance') }} c
JOIN {{ ref('stg_dm__process_catalog') }} pc USING (process)
