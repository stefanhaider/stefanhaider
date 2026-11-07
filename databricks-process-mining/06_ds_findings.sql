-- =====================================================================
-- Dataset "findings" – jedes einzelne Befund-Vorkommen (alle Prozesse)
-- Pfad-Abweichungen (Kontrolle umgangen, Rücksprung, ...) und Regelverstöße
-- (Funktionstrennung, Frist) mit Schweregrad, ausführender Person und Zeitpunkt.
-- Basis für "Befunde je Typ", Drill-down und Audit-Export.
-- =====================================================================
SELECT
  f.*,
  pc.owner AS process_owner
FROM main.data_manager_pm.v_findings f
JOIN main.data_manager_pm.process_catalog pc USING (process);
