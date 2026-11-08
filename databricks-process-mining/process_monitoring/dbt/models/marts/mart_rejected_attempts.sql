-- Vom Data Manager abgewiesene Statuswechsel (Nachweis wirksamer Kontrollen).
SELECT r.*, pc.owner AS process_owner
FROM {{ ref('int_rejected_attempts') }} r
JOIN {{ ref('stg_dm__process_catalog') }} pc USING (process)
