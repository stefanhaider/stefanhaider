# Übergabe-Prompt für den System-Agenten

Kopiere den Block unten als ersten Auftrag an den System-Agenten. Gib ihm das ZIP bzw. das
Repository mit Branch (`stefanhaider/stefanhaider`, `ccr-f1f6041b-rq5je9`, Ordner
`databricks-process-mining/`).

---

```text
Du bist der implementierende Agent für das Prozess- und Governance-Monitoring unseres
"Data Manager" (selbst entwickelte Data-Governance-/Data-Mesh-Applikation: Python-Backend,
Vue.js-Frontend, PostgreSQL).

Es gibt zwei getrennte Teile:
 1. data_manager/: Der Data Manager erzeugt alle Daten fürs Monitoring in seiner PostgreSQL
    (Footprints, Status-Maschine je Release, Soll-Modell, Regeln).
 2. process_monitoring/: ein eigenständiges Databricks Asset Bundle. Data Product = dbt-Projekt,
    dazu Dashboards, Jobs und Alarm. Es liest die Daten nur per Unity Catalog (Foreign Catalog)
    und ist unabhängig von der Applikation.

Vorgehen:
1. Lies AGENTS.md vollständig, dann IMPLEMENTATION_SPEC.md und EVENT_STANDARD.md.
   Öffne mockup/dashboard.html als Zielbild.
2. Führe AP1 aus: `bash tools/verify_all.sh` (mit DM_TEST_PG_DSN auf eine UTF-8-Test-DB). Melde
   das Ergebnis mit Ausgabe.
3. Stelle mir die offenen Fragen aus AGENTS.md Abschnitt 5 gesammelt in einer Nachricht.
   AP5 (Bundle in dev mit Beispieldaten) darfst du vorher machen, sobald du Workspace-Zugang hast.
4. Arbeite die Arbeitspakete der Reihe nach ab. Ein Paket ist erst fertig, wenn seine Prüfung
   bestanden ist. Berichte nach jedem Paket im Format aus AGENTS.md Abschnitt 8.

Leitplanken (AGENTS.md Abschnitt 3):
- strikte Trennung Data Manager / Databricks,
- Data Product nur als dbt-Projekt,
- alles in Databricks als Bundle,
- keine Databricks App, keine Heatmap, kein Sankey,
- der Soll-Prozess wird nie aus dem Code erzeugt,
- Statuswechsel nur über StateMachine.transition(),
- nichts in Produktion, an echten Tabellen, Berechtigungen oder Alarm-Empfängern ohne meine
  Freigabe,
- Ungetestetes als ungetestet melden.
```

---

## Was du dem Agenten zusätzlich geben solltest

| Was | Wofür | Arbeitspaket |
|---|---|---|
| Repository des Data Managers (Arbeits-Branch), Test-Datenbank PostgreSQL (UTF-8) | Einbindung Paket, Migrationen, Tests | AP2–AP4 |
| CI-System bzw. Pipeline-Konfiguration, Deploy-Schritt | CI-Check, `dm-sync-governance` | AP4 |
| Freigabeweg für `governance_model.json` (CODEOWNERS Governance) | Soll-Modell | AP4 |
| Databricks dev-Workspace: Host, SQL Warehouse, Katalog/Schema, Rechte für `bundle deploy` | Bundle, dbt, Dashboard | AP5, AP7–AP9 |
| Databricks: Recht für `CREATE CONNECTION`, Secret-Scope; PostgreSQL read-only User (Rolle `dm_event_reader`) auf dem Read-Replica; Netzwerkweg | Foreign Catalog | AP6 |
| Ansprechpartner der Process Owner | echte Soll-Prozesse, Klärung der Befunde | AP4, AP7 |
| prod: Service Principal, Alarm-Empfänger, Freigabe | Produktion | AP10 |

## Antworten, die du schon vorbereiten kannst (AGENTS.md Abschnitt 5)

1. Web-Framework und ORM des Data Managers (FastAPI/Django/Flask? SQLAlchemy?), CI-System,
   Read-Replica, Netzwerkweg
2. Soll-Prozesse je Objekttyp inklusive Kontrollschritte
3. Regeln für Funktionstrennung und Fristen inklusive Ausnahmen
4. Wann ein Vorgang als abgeschlossen gilt
5. Process Owner und Alarm-Empfänger
6. Databricks-Workspaces, Katalog/Schema, Warehouse, Connection-Rechte, Secret-Scope, Service Principal, Custom Viz
7. Ablage und Freigabe des Soll-Modells
8. Zielwerte und Zeitfenster
