# AGENTS.md – Einstieg für den implementierenden System-Agenten

> Dieses Dokument ist dein Startpunkt. Lies es vollständig, bevor du etwas änderst.
> Die fachliche und technische Spezifikation steht in
> [`IMPLEMENTATION_SPEC.md`](IMPLEMENTATION_SPEC.md); bei Widersprüchen gilt sie.

## 1. Deine Rolle und dein Ziel

Du implementierst ein **Prozess- und Governance-Monitoring für den „Data Manager“**, die selbst
entwickelte Data-Governance- bzw. Data-Mesh-Applikation des Auftraggebers. Der Data Manager hat
ein Python-Backend, ein Vue.js-Frontend und eine PostgreSQL-Datenbank. Er verwaltet Datenkatalog,
Data Contracts, Data Products, Access Requests, Change Approvals und kanonische Datenmodelle.

Es sind **zwei getrennte Teile**:

| Teil | Ordner | Läuft wo | Aufgabe |
|---|---|---|---|
| **1. Data Manager** | `data_manager/` | Repository und Datenbank der Applikation | erzeugt **alle Daten** fürs Monitoring: Footprints, Status-Maschine je Release, Soll-Modell, Regeln, Owner. Dazu CI-Check und Vue-Regeln |
| **2. Data Product** | `process_monitoring/` | eigenes **Databricks Asset Bundle**, **unabhängig** vom Data Manager | **dbt-Projekt = Data Product**, Dashboards, Jobs, Alarm. Liest **nur** über Unity Catalog (Foreign Catalog) |

Der Ordner enthält einen **vollständigen, lokal geprüften Referenzstand**. Deine Aufgabe ist, ihn in
die echten Umgebungen zu bringen und auf echte Daten umzustellen, nicht ihn neu zu erfinden.

## 2. Lesereihenfolge

1. Diese Datei
2. [`IMPLEMENTATION_SPEC.md`](IMPLEMENTATION_SPEC.md): Architektur, Regeln, Dashboard, Abnahmewerte, Risiken
3. [`EVENT_STANDARD.md`](EVENT_STANDARD.md): Event-Format, Einbindung in den Data Manager
4. `mockup/dashboard.html` im Browser (offline): **Zielbild** der drei Dashboard-Seiten
5. `data_manager/README.md` und `data_manager/frontend/README.md`
6. `process_monitoring/README.md`, danach `dbt/models/` (staging → intermediate → marts)

## 3. Leitplanken (nicht verhandelbar)

* **Trennung der Teile:** Das Databricks-Projekt hat **keine** Code- oder Laufzeitabhängigkeit zum
  Data Manager. Die einzige Schnittstelle sind die Tabellen in `governance.*`, gelesen per Foreign
  Catalog. Kein Aufruf von Data-Manager-APIs aus Databricks und kein Schreiben in den Data Manager.
* **Data Product = dbt-Projekt.** Alle Datenmodelle für Dashboards sind dbt-Modelle in
  `process_monitoring/dbt/`, inklusive Tests. Keine handgepflegten Views oder Tabellen daneben.
* **Alles in Databricks als Bundle:** Jobs, Dashboard und Konfiguration sind in
  `process_monitoring/` versioniert und werden per `databricks bundle deploy` ausgerollt.
  Ausnahme: das einmalige Unity-Catalog-Setup (Connection), das Admin-Rechte braucht.
* **Keine Databricks App, keine Heatmap oder Übergangsmatrix, kein Sankey.**
* **Der Soll-Prozess wird nie aus dem Code erzeugt.** `governance_model.json` gehört der Governance
  (CODEOWNERS). Die Status-Maschine (`workflows.py`) gehört der Entwicklung.
* **Logik nur an einer Stelle:** Die Klassifizierung steht in `int_transition_classes` (dbt) und
  `conformance.classify()` (Python). Beide bleiben identisch.
* **Statuswechsel nur über `StateMachine.transition()`.** Die Vue-UI zeigt nur Aktionen aus
  `allowed_next()`. Abgewiesene Versuche gehen über `reject_sink` in eine eigene Transaktion.
* **`governance.process_event` bleibt append-only** (Trigger, Rechte). Databricks liest mit einem
  read-only User, möglichst vom Read-Replica.
* **Keine Produktionsänderungen ohne Freigabe:** kein Deploy auf `prod`, kein Löschen oder
  Überschreiben echter Tabellen, keine Änderung an Berechtigungen, kein Alarm an echte Empfänger,
  ohne Zustimmung des Auftraggebers. Zuerst `dev`.
* **Personenbezogene Daten** (`actor`, `initiator`): Zugriff beschränken; nichts davon in Logs,
  Tickets oder Screenshots außerhalb des Workspace.
* **Ehrlich berichten:** Ungetestetes als ungetestet melden.

## 4. Was bereits geprüft ist (Ausgangslage)

| Bestandteil | Status |
|---|---|
| Data-Manager-Paket `data_manager/python/` | 17 pytest-Tests grün, davon 6 gegen PostgreSQL 16 (append-only, Rollen, Rollback, Kopierlogik, Sync) |
| PostgreSQL-DDL `001_process_event.sql`, `002_governance_model.sql` | gegen PostgreSQL 16 getestet |
| CI-Check `dm-check-workflow` | 8 Befunde, 6 blockierend, Exit-Code 1 (Referenzlauf) |
| dbt-Projekt `process_monitoring/dbt/` | `dbt build` mit Beispieldaten lokal (Spark 4.0.1 + Delta 4.0, dbt-spark Session): **50/50**, inklusive 5 Abnahmetests; zweiter Lauf über den inkrementellen MERGE ebenfalls 50/50 |
| `process_graph.vl.json` | rendert mit den Daten aus `mart_process_graph` ohne Warnungen (Vega-Lite 5/6) |
| Bundle-YAML (`databricks.yml`, `resources/`) | nur YAML-Syntax geprüft; **`databricks bundle validate` ungetestet** (CLI in der Testumgebung nicht verfügbar) |
| `setup/01_unity_catalog_connection.sql`, Job, Dashboard-Import, Custom Viz, `dbt-databricks` | **ungetestet**, Databricks-spezifisch |
| Vue-Bausteine `data_manager/frontend/` | **ungetestet** (kein Build) |

Ausgangslage selbst prüfen: `bash tools/verify_all.sh`, optional mit
`DM_TEST_PG_DSN=postgresql://…/testdb` für die PostgreSQL-Tests.

Voraussetzungen:
- Python 3.10+ mit `pip install pytest "psycopg[binary]" "dbt-core>=1.10" "dbt-spark[session]>=1.9" pyspark==4.0.1`,
- Java 17+,
- Node 18+ mit `cd tools && npm install`.

## 5. Zuerst klären (blockierend)

Siehe IMPLEMENTATION_SPEC.md, Abschnitt 4. Stelle die Fragen gesammelt in einer Nachricht.

1. Data Manager: Web-Framework (FastAPI/Django/Flask?), ORM, CI-System, Read-Replica, Netzwerkweg
   Databricks → PostgreSQL
2. Echte Soll-Prozesse je Objekttyp inklusive **Kontrollschritte**
3. Governance-Regeln (Funktionstrennung, Fristen) inklusive Ausnahmen
4. Regel für laufende Vorgänge
5. Process Owner, Alarm-Empfänger und Kanal
6. Databricks: Workspaces dev/prod, Katalog/Schema, SQL Warehouse, `CREATE CONNECTION`-Recht,
   Secret-Scope, Service Principal (prod), Custom Viz verfügbar?
7. Ablage und Freigabe des Soll-Modells (CODEOWNERS in `data_manager/governance/` oder eigenes Repo)
8. Zielwerte und Zeitfenster

## 6. Arbeitspakete

Arbeite sie in dieser Reihenfolge ab. Ein Paket ist erst fertig, wenn seine Prüfung bestanden ist.

**Teil 1: Data Manager**

| # | Arbeitspaket | Ergebnis | Prüfung |
|---|---|---|---|
| AP1 | **Ausgangslage verifizieren** | Referenzstand läuft lokal | `bash tools/verify_all.sh` → „ALLES BESTANDEN“ (mit `DM_TEST_PG_DSN`) |
| AP2 | **Footprints im Data Manager:** Paket übernehmen, Migrationen `001` + `002`, echte Status-Maschinen in `workflows.py` (inkl. `RELEASES`), alle Statuswechsel über `transition()`, EventStore passend zum ORM, `reject_sink`, Endpoints für `allowed_next`/`transition` | Pull Request im Data-Manager-Repo | Tests grün inkl. PostgreSQL; neue Tests für den ORM-EventStore; kein Code setzt den Status an `transition()` vorbei (Suche oder Lint-Regel) |
| AP3 | **Vue-Frontend:** `useWorkflow`/`WorkflowActions` integrieren, 409-Behandlung, `traceparent` | Pull Request | Buttons zeigen nur erlaubte Aktionen; ein abgewiesener Versuch erscheint als `rejected` in `process_event` |
| AP4 | **Stammdaten und CI:** `governance_model.json` mit den echten Soll-Prozessen (CODEOWNERS Governance), `dm-sync-governance` im Deploy, CI-Schritte `pytest` → `dm-export-workflow` → `dm-check-workflow`, Prozess für `accepted_deviations.json` | Pipeline + Deploy-Schritt | Ein absichtlich eingebauter Übergang, der eine Kontrolle umgeht, lässt den Build scheitern; nach Deploy stehen Release und Status-Maschine in `governance.*` |

**Teil 2: Databricks (Bundle `process_monitoring`)**

| # | Arbeitspaket | Ergebnis | Prüfung |
|---|---|---|---|
| AP5 | **Bundle in dev mit Beispieldaten:** Variablen setzen (Host, `warehouse_id`, Katalog/Schema; in dev ist `use_sample_data: true` voreingestellt), `databricks bundle validate/deploy -t dev`, `databricks bundle run -t dev process_monitoring_refresh` | Data Product mit Beispieldaten im Dev-Schema | `dbt build` im Workspace: alle Tests grün inkl. `acceptance_*`, gleiche Zahlen wie lokal |
| AP6 | **Unity-Catalog-Einbindung:** read-only DB-User (Rolle `dm_event_reader`, Read-Replica), Secrets, `setup/01_unity_catalog_connection.sql` | Foreign Catalog `dm_pg` | `SELECT … FROM dm_pg.governance.process_event` und alle 7 Stammdaten-Tabellen lesbar; Grants für den Job-Principal |
| AP7 | **Data Product auf echten Daten (dev):** in `databricks.yml` für dev `use_sample_data: false` setzen, neu deployen; Seeds `process_graph_layout` und `finding_severity` für die echten Prozesse anpassen | Marts aus echten Dev-Daten | Testvorgang im Dev-Data-Manager erscheint nach dem nächsten Joblauf in `mart_case_conformance`; mehrfacher Lauf ohne Duplikate; Vollständigkeitskontrolle = 0; dbt-Tests grün |
| AP8 | **Dashboard:** Import über die Bundle-Ressource, Custom Viz mit `process_graph.vl.json` einrichten (Felder siehe Spec 6.4), danach `databricks bundle generate dashboard` und versionieren | 3-seitiges Dashboard, Export im Bundle | Aufbau und Verhalten wie im Mockup; Graph für alle Prozesse ohne Konsolenfehler; Filter Prozess/Domäne wirken; helles und dunkles Theme |
| AP9 | **Alarm:** Alarm-Task mit Empfänger = Auftraggeber (dev) | Benachrichtigung | Mit Beispieldaten schlägt der Task fehl und meldet 5 Befunde (1 neu); ohne kritische Befunde ist er grün |
| AP10 | **Produktion** (nur nach Freigabe): `-t prod`, Service Principal, Grants, echte Empfänger, Zeitplan | Produktivbetrieb | Abnahme durch den Auftraggeber |

## 7. Definition of Done

- [ ] AP1–AP9 mit bestandener Prüfung; AP10 nach Freigabe
- [ ] Dashboard-Export aus dem Workspace im Bundle versioniert und ersetzt den Entwurf
- [ ] `bash tools/verify_all.sh` weiterhin grün; neue Logik mit Tests abgedeckt (pytest bzw. dbt-Tests)
- [ ] Dokumente aktualisiert: geklärte Fragen eingetragen, Abweichungen begründet
- [ ] Übergabebericht an den Auftraggeber (siehe 8)

## 8. Berichtsformat

Am Ende jedes Arbeitspakets kurz berichten:
- **Erledigt:** was, mit welchem Prüfergebnis (Zahlen bzw. Ausgabe)
- **Ungetestet bzw. offen:** ehrlich benennen, mit Grund
- **Entscheidungen:** was du festgelegt hast und warum
- **Nächster Schritt und Fragen an den Auftraggeber**

## 9. Dateien auf einen Blick

| Bereich | Dateien |
|---|---|
| Data Manager: Code | `data_manager/python/src/datamanager_governance/` (`state_machine.py`, `workflows.py`, `event_store.py`, `governance_sync.py`, `export.py`, `conformance.py`) |
| Data Manager: Datenbank | `data_manager/python/sql/postgres/001_process_event.sql`, `002_governance_model.sql` |
| Governance | `data_manager/governance/governance_model.json`, `accepted_deviations.json`, `workflow_definition.json` |
| Frontend | `data_manager/frontend/` |
| CI | `data_manager/ci/` |
| Databricks-Bundle | `process_monitoring/databricks.yml`, `resources/`, `setup/`, `src/` |
| Data Product (dbt) | `process_monitoring/dbt/` (`models/{sample,staging,intermediate,marts}`, `seeds/`, `tests/`, `macros/`) |
| Zielbild | `mockup/` |
| Prüfung | `tools/verify_all.sh`, `run_dbt_local.sh`, `export_graph_json.py`, `check_vega_spec.mjs` |
