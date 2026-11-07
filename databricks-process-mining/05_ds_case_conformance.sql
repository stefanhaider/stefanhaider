-- =====================================================================
-- Dataset "case_conformance" – ein Datensatz je Vorgang (alle Prozesse)
-- Basis für KPIs, Trends und die Fall-Liste (Drill-down).
--   is_conformant : Pfad entspricht dem Soll-Prozess
--   is_compliant  : zusätzlich keine Verstöße gegen Funktionstrennung/Fristen
--   has_*         : Flags je Befund-Art; findings = Liste der Befunde
-- =====================================================================
SELECT
  c.*,
  pc.owner AS process_owner
FROM main.data_manager_pm.v_case_conformance c
JOIN main.data_manager_pm.process_catalog pc USING (process);
