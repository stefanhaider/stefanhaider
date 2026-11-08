-- =====================================================================
-- Dataset "rejected_attempts" – vom Data Manager abgewiesene Statuswechsel
-- (event_type = 'rejected'). Nachweis, dass Kontrollen technisch greifen,
-- und Frühindikator, wo Anwender eine Umgehung versuchen.
-- =====================================================================
SELECT
  r.*,
  pc.owner AS process_owner
FROM main.data_manager_pm.v_rejected_attempts r
JOIN main.data_manager_pm.process_catalog pc USING (process);
