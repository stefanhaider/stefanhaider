# AGENTS.md – Einstieg für den implementierenden System-Agenten

> Dieses Dokument ist dein Startpunkt. Lies es vollständig, bevor du etwas änderst.
> Die fachliche und technische Spezifikation steht in
> [`IMPLEMENTATION_SPEC.md`](IMPLEMENTATION_SPEC.md); bei Widersprüchen gilt sie.

## 1. Deine Rolle und dein Ziel

Du implementierst ein **Prozess- und Governance-Monitoring für den „Data Manager“**, die selbst
entwickelte Data-Governance- bzw. Data-Mesh-Applikation des Auftraggebers (Python). Sie
verwaltet Datenkatalog, Data Contracts, Data Products, Access Requests, Change Approvals und
kanonische Datenmodelle.

Das Ergebnis beantwortet vier Fragen:

1. Werden die Soll-Prozesse eingehalten?
2. Lässt der Data Manager Wege zu, die er nicht zulassen sollte (umgangene Kontrollen)?
3. Werden Governance-Regeln verletzt (Funktionstrennung, Fristen)?
4. Passt die Status-Maschine des Systems zum Soll-Prozess? Auch vor jedem Release als CI-Check.

**Zielplattform:** Databricks (Delta, Views, SQL Warehouse, AI/BI Dashboard mit Custom Viz,
SQL Alerts) und das Python-Repository des Data Managers.

Der Ordner enthält einen **vollständigen, lokal geprüften Referenzstand**. Deine Aufgabe ist,
ihn **in die echte Umgebung zu bringen und auf echte Daten umzustellen**, nicht ihn neu zu
erfinden.

## 2. Lesereihenfolge

1. Diese Datei
2. [`IMPLEMENTATION_SPEC.md`](IMPLEMENTATION_SPEC.md): Regeln, Datenformate, Dashboard,
   Abnahmewerte, Risiken
3. [`EVENT_STANDARD.md`](EVENT_STANDARD.md): Event-Format und Einbindung in den Data Manager
4. `dashboard.html` im Browser (offline lauffähig): **Zielbild der Oberfläche**; Seiten
   „Übersicht“, „Prozessdetail“ und „System-Konformität“
5. Code: `02_process_model.sql` → `03_views.sql` → `04_…` bis `10_…` → `python/` → `ci/`

## 3. Leitplanken (nicht verhandelbar)

* **Keine Databricks App.** Nur Delta-Tabellen, Views, AI/BI Dashboard, Custom Viz, SQL Alerts
  und Jobs.
* **Keine Heatmap oder Übergangsmatrix, kein Sankey** im Dashboard.
* **Der Soll-Prozess wird nie aus dem Code erzeugt.** `governance_model.json` bzw. die Tabellen
  `process_model_*` gehören der Governance. Die Status-Maschine (`python/…/workflows.py`,
  `system_allowed_transitions`) gehört der Entwicklung. Beide bleiben getrennt.
* **Logik nur an einer Stelle:**
  - Klassifizierungsregeln in `v_transition_classes` (SQL) und `conformance.classify()` (Python),
    beide identisch halten,
  - Konfiguration nur in `02_process_model.sql` bzw. den JSON-Dateien in `config/`.
* **Statuswechsel im Data Manager nur über `StateMachine.transition()`.** Abgewiesene Versuche
  über `reject_sink` in eigener Transaktion.
* **Keine Produktionsänderungen ohne Freigabe:** Kein Deploy in Produktion, kein Löschen oder
  Überschreiben echter Tabellen, keine Änderung an Berechtigungen und kein Versand von Alerts an
  echte Empfänger, ohne dass der Auftraggeber zugestimmt hat. Arbeite zuerst in einem Dev-Schema.
* **Personenbezogene Daten** (`actor`, `initiator`): Zugriff beschränken; nichts davon in Logs,
  Tickets oder Screenshots außerhalb des Workspace.
* **Ehrlich berichten:** Was du nicht testen konntest, meldest du als ungetestet, nicht als fertig.

## 4. Was bereits geprüft ist (Ausgangslage)

| Bestandteil | Status |
|---|---|
| SQL 01–10 (Modell, Views, Datasets, Alert) | lokal mit Apache Spark 4.0.1 geprüft, alle Abnahmewerte als Assertions in `tools/local_sql_check.py` |
| `process_graph.vl.json` | rendert mit Vega-Lite 5.23 und 6.5 ohne Warnungen (`tools/check_vega_spec.mjs`) |
| Python-Paket `python/` | 10 pytest-Tests grün; Export der Status-Maschine identisch mit `config/workflow_definition.json` |
| CI-Check | 8 Befunde, 6 blockierend, Exit-Code 1 (Referenzlauf) |
| `11_load_config_from_json.sql`, `12_ingest_events.sql` | **ungetestet** (Databricks-spezifisch) |
| `process_mining.lvdash.json` | **ungetestet**, Format undokumentiert (Entwurf) |
| Custom Viz im Workspace | **ungetestet** (Public Preview) |
| Alles in einem echten Databricks-Workspace | **ungetestet**, das ist deine Hauptaufgabe |

Ausgangslage selbst prüfen: `bash tools/verify_all.sh`. Voraussetzungen: Python 3.10+, Java 17+
mit `pip install pyspark==4.0.1 pytest`, Node 18+ mit `cd tools && npm install`.

## 5. Zuerst klären (blockierend)

Frage den Auftraggeber, bevor du die Arbeitspakete 3 ff. beginnst. Details stehen in
IMPLEMENTATION_SPEC.md, Abschnitt 3.

1. Web-Framework und ORM des Data Managers (FastAPI, Django, Flask? SQLAlchemy/Postgres?) und
   das CI-System
2. Echte Soll-Prozesse je Objekttyp: Status, erlaubte Übergänge, Endzustände, **Kontrollschritte**
3. Governance-Regeln (Funktionstrennung, Fristen) inkl. Ausnahmen (technische Accounts, Notfälle)
4. Regel für **laufende Vorgänge** (wann gilt ein Vorgang als abgeschlossen?)
5. Process Owner, Alarm-Empfänger und Kanal (E-Mail, Teams/Slack, Ticket)
6. Databricks: Workspace, Katalog und Schema (Dev/Prod), Volume für Events, ob Custom Viz
   verfügbar ist, SQL Warehouse
7. Ablage des Soll-Modells (eigenes Governance-Repository mit Freigaben?)
8. Zielwerte (Konformitätsziel je Prozess) und Zeitfenster („aktuell“ 4 Wochen, „neu“ 8 Wochen)

## 6. Arbeitspakete

Arbeite sie in dieser Reihenfolge ab. Jedes Paket ist erst fertig, wenn seine Prüfung bestanden ist.

| # | Arbeitspaket | Ergebnis | Prüfung |
|---|---|---|---|
| AP1 | **Ausgangslage verifizieren** | Referenzstand läuft lokal | `bash tools/verify_all.sh` → „ALLES BESTANDEN“ |
| AP2 | **Dev-Schema in Databricks** mit Beispieldaten: `01`, `02`, `03` ausführen (Katalog/Schema anpassen) | Tabellen und Views im Dev-Schema | Abnahmewerte aus IMPLEMENTATION_SPEC.md Abschnitt 10 per SQL im Workspace reproduziert, gleiche Zahlen wie lokal |
| AP3 | **Dashboard im Workspace** (3 Seiten) nach Abschnitt 8 bzw. `dashboard.html`. Datasets 04–07, 09, 10; Parameter `:process` und `:domain`. Custom Viz mit `process_graph.vl.json`; Felder ohne Aggregation: `row_type, id, src, tgt, cases, median_wait_h, x, y, w, h, seq, shape, node_kind, conformance, is_control, finding_type, system_status` | Dashboard, als `.lvdash.json` exportiert und versioniert | Zahlen stimmen mit dem Mockup überein; Graph für alle 3 Prozesse ohne Konsolenfehler; Tooltips; helles und dunkles Theme |
| AP4 | **SQL Alert** aus `08_…` | Alert (Dev: Empfänger = Auftraggeber) | Alert löst mit Beispieldaten aus (5 Zeilen, 1 neu) |
| AP5 | **Data Manager einbinden** (Python): Paket übernehmen, echte Status-Maschinen in `workflows.py`, alle Statuswechsel über `transition()`, Outbox passend zum ORM, `reject_sink` | Pull Request im Data-Manager-Repo | Tests grün; neue Tests für die ORM-Outbox; kein Code setzt den Status an `transition()` vorbei (Suche oder Lint-Regel) |
| AP6 | **Event-Pipeline:** `dm-publish-events` als Job, Volume, `12_ingest_events.sql`; `event_log` wird zur View auf echte Events | Events fließen von Dev-Data-Manager nach Databricks | Testvorgang im Dev-Data-Manager erscheint innerhalb des Job-Intervalls in `event_log`; abgewiesener Versuch erscheint als `rejected`; keine Duplikate |
| AP7 | **CI-Check** in die Release-Pipeline (`pytest`, `dm-export-workflow`, `dm-check-workflow`); Prozess für genehmigte Ausnahmen mit der Governance | Pipeline-Schritt + `accepted_deviations.json` im Governance-Repo | Ein absichtlich eingebauter Übergang, der eine Kontrolle umgeht, lässt den Build scheitern |
| AP8 | **Konfiguration aus JSON** (`11_…`) als Job nach Release bzw. Modellfreigabe; Historie der Status-Maschine | `system_allowed_transitions` mit `valid_from`/`valid_to` | Zwei Releases nacheinander laden: entfernter Übergang bekommt `valid_to`, neuer wird geöffnet |
| AP9 | **Echte Soll-Prozesse und Regeln** in `governance_model.json` bzw. `02_…`, Layout in `process_graph_layout`; Regel für laufende Vorgänge | Konfiguration für Produktion | Befunde mit den Process Ownern durchgesprochen: echte Lücke oder fehlender Modelleintrag? |
| AP10 | **Produktion** (nur nach Freigabe): Prod-Schema, Berechtigungen, Alert-Empfänger, Job-Zeitpläne; bei großem Volumen `v_transitions`/`v_findings` materialisieren | Produktivbetrieb | Abnahme durch den Auftraggeber |

## 7. Definition of Done

- [ ] AP1–AP9 mit bestandener Prüfung; AP10 nach Freigabe
- [ ] Dashboard-Export (`.lvdash.json`) aus dem Workspace versioniert und ersetzt den Entwurf
- [ ] `bash tools/verify_all.sh` weiterhin grün; neue Logik mit Tests oder Assertions abgedeckt
- [ ] Dokumente aktualisiert: geklärte Fragen eingetragen, Abweichungen vom Referenzstand begründet
- [ ] Übergabebericht an den Auftraggeber (siehe 8)

## 8. Berichtsformat

Am Ende jedes Arbeitspakets kurz berichten:
- **Erledigt:** was, mit welchem Prüfergebnis (Zahlen bzw. Ausgabe)
- **Ungetestet bzw. offen:** ehrlich benennen, mit Grund
- **Entscheidungen:** was du festgelegt hast und warum (insbesondere Abweichungen von der
  Spezifikation)
- **Nächster Schritt und Fragen an den Auftraggeber**

## 9. Dateien auf einen Blick

| Bereich | Dateien |
|---|---|
| Konfiguration | `02_process_model.sql`, `config/governance_model.json`, `config/workflow_definition.json`, `ci/accepted_deviations.json` |
| Logik | `03_views.sql` (7 Views), `python/src/datamanager_governance/conformance.py` |
| Dashboard-Datasets | `04_…` bis `07_…`, `09_…`, `10_…`; Alert `08_…` |
| Produktion | `11_load_config_from_json.sql`, `12_ingest_events.sql` |
| Data Manager | `python/` (Paket + Tests), `EVENT_STANDARD.md`, `examples/` |
| CI | `ci/check_workflow_conformance.py`, `ci/github-actions-example.yml` |
| Prüfung | `tools/verify_all.sh`, `tools/local_sql_check.py`, `tools/check_vega_spec.mjs` |
| Zielbild | `dashboard.html`, `dashboard_*preview.png`, `process_graph_preview.png` |
| Beispieldaten | `01_sample_event_log.sql` (nur Dev/Test; wird in AP6 durch echte Events ersetzt) |
