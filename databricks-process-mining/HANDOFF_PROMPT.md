# Übergabe-Prompt für den System-Agenten

Kopiere den Block unten als ersten Auftrag an den System-Agenten. Lege den Ordner
`databricks-process-mining/` (bzw. das ZIP) in seinen Arbeitsbereich oder nenne ihm das
Repository und den Branch (`stefanhaider/stefanhaider`, `ccr-f1f6041b-rq5je9`).

---

```text
Du bist der implementierende Agent für das Prozess- und Governance-Monitoring unseres
"Data Manager" (selbst entwickelte Data-Governance-/Data-Mesh-Applikation in Python).

Im Ordner databricks-process-mining/ liegt ein vollständiger, lokal geprüfter Referenzstand:
SQL für Databricks, ein Python-Paket für den Data Manager, CI-Check, Dashboard-Mockup und
Prüfwerkzeuge.

1. Lies zuerst AGENTS.md vollständig, dann IMPLEMENTATION_SPEC.md und EVENT_STANDARD.md.
   Öffne dashboard.html als Zielbild der Oberfläche.
2. Führe AP1 aus: `bash tools/verify_all.sh`. Melde das Ergebnis mit Ausgabe. Installiere bei
   Bedarf pyspark==4.0.1, pytest und Java 17+, und führe in tools/ `npm install` aus.
3. Stelle mir danach die offenen Fragen aus AGENTS.md Abschnitt 5 gesammelt in einer Nachricht.
   Beginne AP3 ff. erst, wenn sie beantwortet sind. AP2 (Dev-Schema mit Beispieldaten) darfst du
   vorher machen, sobald du Workspace-Zugang hast.
4. Arbeite die Arbeitspakete AP2–AP9 der Reihe nach ab. Ein Paket ist erst fertig, wenn seine
   Prüfung bestanden ist. Berichte nach jedem Paket im Format aus AGENTS.md Abschnitt 8.

Leitplanken (AGENTS.md Abschnitt 3):
- keine Databricks App,
- keine Heatmap und kein Sankey,
- der Soll-Prozess wird nie aus dem Code erzeugt,
- Statuswechsel nur über StateMachine.transition(),
- nichts in Produktion, an echte Tabellen, Berechtigungen oder Alert-Empfänger ohne meine
  ausdrückliche Freigabe,
- Ungetestetes als ungetestet melden.
```

---

## Was du dem Agenten zusätzlich geben solltest

| Was | Wofür | Arbeitspaket |
|---|---|---|
| Zugang zum Databricks-Workspace (Dev), Katalog/Schema, SQL Warehouse | Tabellen, Views, Dashboard, Alert | AP2–AP4 |
| Zugang zum Repository des Data Managers (Branch für die Arbeit) | Einbindung des Pakets | AP5 |
| PostgreSQL: Test-Datenbank (UTF-8) für die Tests; Dev-DB für die Migration; read-only User (Rolle `dm_event_reader`) auf dem Read-Replica; Netzwerkweg von Databricks (Private Link/VPC-Peering) | Migration, Tests, Lakehouse Federation | AP5, AP6 |
| Databricks: Recht für `CREATE CONNECTION`, Secret-Scope für DB-Zugangsdaten | Connection und Foreign Catalog | AP6 |
| Zugang zum CI-System bzw. Pipeline-Konfiguration | CI-Check | AP7 |
| Governance-Repository oder Ablageort für `governance_model.json` | Soll-Modell mit Freigaben | AP7–AP9 |
| Ansprechpartner der Process Owner | Klärung der Befunde, echte Soll-Prozesse | AP9 |

## Antworten, die du schon vorbereiten kannst (AGENTS.md Abschnitt 5)

1. Framework, ORM und CI-System des Data Managers (Datenbank: PostgreSQL, bereits geklärt); Read-Replica und Netzwerkweg
2. Soll-Prozesse je Objekttyp inklusive Kontrollschritte
3. Regeln für Funktionstrennung und Fristen inklusive Ausnahmen
4. Wann ein Vorgang als abgeschlossen gilt
5. Process Owner und Alarm-Empfänger
6. Workspace, Katalog und Schema, `CREATE CONNECTION`-Recht und Secret-Scope, Verfügbarkeit von Custom Viz
7. Ablage des Soll-Modells
8. Zielwerte und Zeitfenster
