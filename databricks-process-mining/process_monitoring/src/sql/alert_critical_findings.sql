-- Alarm-Task des Jobs process_monitoring_refresh (nach dbt build).
-- Schlägt fehl, wenn neue oder in den letzten 7 Tagen aufgetretene kritische Befunde vorliegen;
-- der Job verschickt dann die E-Mail an var.alert_emails. Details: Tabelle mart_alert_critical_findings
-- bzw. Dashboard-Seite "Übersicht" (Banner und Handlungsbedarf).
-- Alternative: Databricks SQL Alert direkt auf mart_alert_critical_findings (Bedingung: Zeilen > 0).
SELECT
  CASE WHEN COUNT(*) > 0 THEN
    raise_error(concat('Kritische Governance-Befunde: ',
      array_join(collect_list(concat(process, ': ', finding, ' (', cases_last_7d, ' in 7 Tagen',
                                     IF(is_new, ', NEU', ''), '; ', process_owner, ')')), ' | ')))
  END AS result
FROM IDENTIFIER(:catalog || '.' || :schema || '.mart_alert_critical_findings');
