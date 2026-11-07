# Data Manager – Prozess- & Governance-Monitoring (Databricks AI/BI)

Process Mining speziell für den **Data Manager**, unsere Data-Governance- bzw.
Data-Mesh-Applikation für Datenkatalog, Data Contracts, Data Products, Access Requests, Change
Approvals und kanonische Datenmodelle. Das Monitoring misst, ob die **Ist-Prozesse den definierten
Soll-Prozessen entsprechen**, und macht **Prozesslücken und Governance-Brüche** sichtbar:

* **Kontrolle umgangen:** z. B. Berechtigung ohne Security-Prüfung, Datenprodukt ohne
  Qualitätsprüfung, Contract-Änderung ohne Review
* **Funktionstrennung verletzt:** Antragsteller genehmigt den eigenen Antrag
* **Frist überschritten:** z. B. Zugriff nicht innerhalb von 5 Tagen
* je Befund: **neu**, **tritt weiterhin auf** oder **nicht mehr aufgetreten**. Das beantwortet,
  ob der Data Manager den Weg noch zulässt.
* **Alarm** an den Process Owner bei neuen bzw. aktuellen kritischen Befunden

Umgesetzt ohne Databricks App, nur mit Delta-Tabellen, Views, AI/BI Dashboard (inkl. Custom
Viz mit Vega-Lite) und SQL Alert.

**Für die Implementierung:** [`IMPLEMENTATION_SPEC.md`](IMPLEMENTATION_SPEC.md). Dort stehen alle
Regeln, Datenformate, Abnahmewerte und offenen Fragen.

## Übersicht

![Übersicht](dashboard_preview.png)

## Prozessdetail mit Soll-Ist-Prozessgraph

![Prozessdetail](dashboard_detail_preview.png)

Im Graphen sind erlaubte Wege grau. Rot gestrichelt sind **umgangene Kontrollen**, orange
gestrichelt sonstige Abweichungen. ◆ markiert Kontrollschritte.

## Dateien

| Datei | Inhalt |
|---|---|
| `01_sample_event_log.sql` | Beispiel-Eventlog: 3 Prozesse, 1.000 Vorgänge, mit typischen Governance-Lücken |
| `02_process_model.sql` | **Konfiguration:** Prozesse, Soll-Prozesse, Kontrollschritte, Regeln, Schweregrade, Graph-Layout |
| `03_views.sql` | Auswertungslogik als Views (Übergänge, Regelverstöße, Befunde, Konformität je Vorgang) |
| `04_ds_process_graph.sql` | Dataset für den Prozessgraphen (Layout in SQL) |
| `05_ds_case_conformance.sql` | Dataset: Vorgänge |
| `06_ds_findings.sql` | Dataset: Befund-Vorkommen |
| `07_ds_findings_summary.sql` | Dataset: Befunde mit Status und Verantwortlichem |
| `08_alert_critical_findings.sql` | Abfrage für den SQL Alert |
| `process_graph.vl.json` | Vega-Lite-Spezifikation für Custom Viz |
| `process_mining.lvdash.json` | Dashboard-Entwurf zum Import (ungetestet; ohne Prozessgraph, dafür ein Platzhalter) |
| `dashboard.html` | Interaktives Mockup, im Browser öffnen, funktioniert offline |
| `IMPLEMENTATION_SPEC.md` | Übergabe zur Implementierung |

## Schnellstart

1. `01_…` (oder eine View auf das echte Data-Manager-Log), `02_…` und `03_…` im SQL-Editor
   ausführen.
2. Dashboard: `process_mining.lvdash.json` importieren oder manuell nach der Spezifikation
   aufbauen. Den Prozessgraphen als Custom Viz mit `04_…` und `process_graph.vl.json` anlegen.
3. SQL Alert mit `08_…` einrichten.

Neue Prozesse oder Prozessänderungen pflegst du **nur in `02_process_model.sql`**.

## Status

Alle SQL-Dateien sind lokal mit Apache Spark 4.0.1 getestet. Die Vega-Lite-Spezifikation
rendert in Vega-Lite 5 und 6 ohne Warnungen. In einem echten Databricks-Workspace ist **noch
nichts** getestet, das ist Teil des Implementierungsauftrags.
