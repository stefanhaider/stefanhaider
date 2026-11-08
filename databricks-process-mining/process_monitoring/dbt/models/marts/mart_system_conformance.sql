-- Soll-Prozess vs. Status-Maschine vs. Ist je Übergang (System-Prozess-Konformität).
SELECT v.*, pc.owner AS process_owner,
       CASE v.severity WHEN 'kritisch' THEN 1 WHEN 'hoch' THEN 2 WHEN 'mittel' THEN 3 ELSE 4 END AS severity_rank
FROM {{ ref('int_system_conformance') }} v
JOIN {{ ref('stg_dm__process_catalog') }} pc USING (process)
