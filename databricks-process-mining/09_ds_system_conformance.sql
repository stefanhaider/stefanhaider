-- =====================================================================
-- Dataset "system_conformance" – Soll-Prozess vs. Status-Maschine des Data Managers vs. Ist
-- Ein Datensatz je Übergang (alle Prozesse).
--
-- system_category:
--   Umgehung außerhalb des Workflows  – kommt vor, war laut Status-Maschine aber nicht erlaubt
--                                       (Admin-API, Batch, Direktzugriff) – kritisch
--   Soll-Schritt nicht implementiert  – Soll verlangt/erlaubt ihn, das System bietet ihn nicht an
--   System lässt mehr zu – genutzt    – System erlaubt, Soll nicht, und es passiert
--   System lässt mehr zu – latent     – System erlaubt, Soll nicht, bisher ungenutzt (Risiko vor Schaden)
--   Nicht mehr erlaubt                – früher vom System erlaubt, im aktuellen Release entfernt
--   Vom System abgewiesen             – nicht erlaubt, Versuche wurden abgewiesen (Kontrolle wirkt)
--   Konform                           – Soll und System stimmen überein
-- =====================================================================
SELECT
  v.*,
  pc.owner AS process_owner
FROM main.data_manager_pm.v_system_conformance v
JOIN main.data_manager_pm.process_catalog pc USING (process)
ORDER BY CASE v.severity WHEN 'kritisch' THEN 1 WHEN 'hoch' THEN 2 WHEN 'mittel' THEN 3 ELSE 4 END,
         v.process, v.observed_cases DESC;
