# Spezifikation: Prozess- und Governance-Monitoring für den „Data Manager“

> Vollständige fachliche und technische Spezifikation. Einstieg für den implementierenden Agenten
> ist [`AGENTS.md`](AGENTS.md); bei Widersprüchen gilt dieses Dokument.

---

## 1. Kontext und Ziel

Der **Data Manager** ist die selbst entwickelte Data-Governance- bzw. Data-Mesh-Applikation des
Auftraggebers:
- **Backend:** Python,
- **Frontend:** Vue.js,
- **Datenbank:** PostgreSQL.

Er verwaltet Datenkatalog, Data Contracts, Data Products, Applikationen, Access Requests, Change
Approvals und kanonische Datenmodelle. Die Prozesse dahinter sind definiert und implementiert.

**Ziel:** messen, ob die Ist-Prozesse den Soll-Prozessen entsprechen, und **informiert werden**, wenn
Prozesslücken oder Governance-Brüche sichtbar werden. Vier Fragen:

1. **Werden die Soll-Prozesse eingehalten?** Konformitätsrate je Prozess und Verlauf.
2. **Lässt der Data Manager Wege zu, die er nicht zulassen sollte?** Umgangene Kontrollen. Ist der
   Befund **neu**, tritt er **weiterhin auf**, oder ist er **behoben**?
3. **Werden Governance-Regeln verletzt?** Funktionstrennung, Fristen.
4. **Passt die Status-Maschine zum Soll-Prozess (System-Prozess-Konformität)?** Auch latente Lücken,
   Umgehungen am Workflow vorbei und als CI-Check vor jedem Release.

Fachlich ist das Conformance Checking auf Directly-Follows-Beziehungen plus Regelprüfungen. Es ist
**kein** generisches Process-Mining-Tool.

### Rahmenbedingungen (vom Auftraggeber festgelegt)

* **Zwei getrennte Teile:**
  1. **Data Manager** (Applikation): erzeugt **alle Daten**, die das Monitoring braucht, in seiner
     PostgreSQL-Datenbank.
  2. **Databricks-Projekt `process_monitoring`**: ein **Databricks Asset Bundle**, das **komplett
     unabhängig** vom Data Manager läuft. Es enthält das Data Product, Dashboards und Jobs. Die
     einzige Verbindung sind die Daten, per **Unity Catalog** (Foreign Catalog, Lakehouse
     Federation) eingebunden.
* **Data Product = dbt-Projekt.** Die Datenmodelle für die Dashboards sind dbt-Modelle.
* **Keine Databricks App**, **keine Heatmap oder Übergangsmatrix**, **kein Sankey.** Stattdessen ein
  Prozessgraph im Process-Mining-Stil (Custom Viz mit Vega-Lite).
* Sprache Deutsch, Zahlenformat deutsch.
* Erweiterbar auf weitere Prozesse (Change Approval, kanonische Datenmodelle, …) **nur über Daten
  bzw. Konfiguration**.

---

## 2. Architektur

```
┌──────────────────────── Data Manager (Applikation) ───────────────────────┐
│ Vue-Frontend ─► Python-Backend ─► StateMachine.transition()               │
│                                       │ gleiche Transaktion               │
│ PostgreSQL  governance.process_event  ◄┘ (append-only Footprints)         │
│             governance.app_release / workflow_transition   ◄─ dm-sync-governance (Deploy)
│             governance.process_catalog / process_model_* / governance_rule ◄─ governance_model.json
│ CI: pytest · dm-export-workflow · dm-check-workflow (Status-Maschine vs. Soll)            │
└───────────────────────────────────────┬───────────────────────────────────┘
                                        │ Unity Catalog: Connection + Foreign Catalog dm_pg
                                        │ (read-only User dm_event_reader, möglichst Read-Replica)
┌───────────────────── Databricks Asset Bundle process_monitoring ──────────┐
│ dbt-Projekt (Data Product):                                               │
│   staging (stg_dm__*; process_event inkrementell per MERGE)               │
│   intermediate (Klassifizierung, Historie der Status-Maschine, Befunde)   │
│   03_product (mart_*, Data Contract) ─► AI/BI Dashboard, Alarm          │
│ Job process_monitoring_refresh (alle 15 Min.): dbt build ─► Alarm-Task    │
└───────────────────────────────────────────────────────────────────────────┘
```

---

## 3. Paketstruktur

| Pfad | Teil | Inhalt |
|---|---|---|
| `data_manager/python/` | Data Manager | Paket `datamanager_governance`: `events.py`, `state_machine.py` (`transition`, `allowed_next`), `workflows.py` (**Status-Maschine = System-Ebene**, `RELEASES`), `event_store.py`, `export.py`, `conformance.py`, `governance_sync.py`; 17 pytest-Tests (6 gegen PostgreSQL) |
| `data_manager/python/sql/postgres/001_process_event.sql` | Data Manager | append-only Footprint-Tabelle, Trigger, Rollen `dm_event_writer`/`dm_event_reader`, UTF-8-Prüfung |
| `data_manager/python/sql/postgres/002_governance_model.sql` | Data Manager | Stammdaten-Tabellen fürs Monitoring, Rolle `dm_governance_sync` |
| `data_manager/governance/` | Governance (CODEOWNERS) | `governance_model.json` (Soll-Prozesse, Kontrollen, Regeln, Owner), `accepted_deviations.json`, `workflow_definition.json` (Export, erzeugt aus `workflows.py`) |
| `data_manager/frontend/` | Data Manager | Vue-3-Bausteine (`useWorkflow.ts`, `WorkflowActions.vue`), Regeln für das Frontend |
| `data_manager/ci/` | Data Manager | CI-Wrapper, Pipeline-Beispiel (GitHub Actions mit PostgreSQL-Service) |
| `data_manager/examples/` | Data Manager | Demo, Beispiel-Events |
| `process_monitoring/databricks.yml` | Databricks | Bundle-Definition, Variablen, Targets dev/prod |
| `process_monitoring/resources/` | Databricks | Job `process_monitoring_refresh` (dbt + Alarm), Dashboard-Ressource |
| `process_monitoring/setup/01_unity_catalog_connection.sql` | Databricks | einmalig: Connection, Foreign Catalog, Grants, Vollständigkeitskontrolle |
| `process_monitoring/dbt/` | Databricks | **dbt-Projekt = Data Product**: `models/01_staging`, `02_intermediate`, `03_product` (Data Contract), `sample_data/`, Seeds, Tests |
| `process_monitoring/src/dashboards/` | Databricks | `process_monitoring.lvdash.json` (Entwurf), `process_graph.vl.json` (Custom Viz) |
| `process_monitoring/src/sql/alert_critical_findings.sql` | Databricks | Alarm-Task |
| `mockup/` | – | interaktives Zielbild `dashboard.html` (offline), Screenshots |
| `tools/` | – | `verify_all.sh`, `run_dbt_local.sh`, `export_graph_json.py`, `check_vega_spec.mjs` |

**Geprüft:** Alle Python-Tests (inklusive PostgreSQL 16), `dbt build` mit Beispieldaten lokal auf
Spark 4.0.1 mit Delta 4.0 (50/50 inklusive Abnahmetests, auch beim zweiten, inkrementellen Lauf),
Render-Check der Vega-Lite-Spezifikation (v5/v6).

**Nicht geprüft:** alles in einem echten Databricks-Workspace, also Bundle-Deploy, Job,
`dbt-databricks` gegen das SQL Warehouse, Foreign Catalog, Dashboard-Import, Custom Viz und
Alarm-Task. Außerdem `databricks bundle validate` (die CLI war in der Testumgebung nicht
verfügbar) und die Vue-Bausteine (kein Build).

---

## 4. Vor dem Start klären

1. **Data Manager:** Web-Framework (FastAPI/Django/Flask?), ORM (SQLAlchemy?), CI-System, Read-Replica,
   Netzwerkweg Databricks → PostgreSQL (Private Link/VPC-Peering).
2. **Echte Soll-Prozesse** je Objekttyp: Status, erlaubte Übergänge, Endzustände, **Kontrollschritte**.
3. **Governance-Regeln** (Funktionstrennung, Fristen) inklusive Ausnahmen (technische Accounts, Notfälle).
4. **Laufende Vorgänge:** Wann gilt ein Vorgang als abgeschlossen?
5. **Process Owner, Alarm-Empfänger** und Kanal.
6. **Databricks:** Workspaces dev/prod, Katalog/Schema, SQL Warehouse, `CREATE CONNECTION`-Recht,
   Secret-Scope, Service Principal für prod, Custom Viz verfügbar?
7. **Ablage und Freigabe des Soll-Modells:** `data_manager/governance/` mit CODEOWNERS =
   Governance, oder ein eigenes Repository?
8. **Zielwerte** (Konformitätsziel je Prozess) und Zeitfenster („aktuell“ 28 Tage, „neu“ 56 Tage).

---

## 5. Data Manager: Daten erzeugen (Teil 1)

### 5.1 Footprints: `governance.process_event`

Jeder Statuswechsel läuft durch `StateMachine.transition()` und schreibt **in derselben Transaktion**
genau ein Event. Felder nach [`EVENT_STANDARD.md`](EVENT_STANDARD.md):

`event_id`, `event_type` (`transition`/`rejected`), `process`, `case_id`, `object_version`, `domain`,
`from_activity`, `activity`, `actor`, `channel` (ui/api/admin_api/batch/migration/system),
`app_version`, `workflow_version`, `trace_id`, `reason`, `event_ts`, `recorded_at` (DB-Zeit), `seq`.

* **Append-only:** Trigger verbieten UPDATE, DELETE und TRUNCATE.
* **Rollen:** App = `dm_event_writer` (nur INSERT), Databricks = `dm_event_reader` (nur SELECT).
* **Abgewiesene Versuche** (`TransitionRejected`) werden über `reject_sink` in einer **eigenen**
  Transaktion gespeichert. So überleben sie den Rollback der Anwendung (getestet, auch nach
  vorheriger Schreiboperation).
* **Vue:** Die UI zeigt nur Aktionen aus `allowed_next()` und behandelt HTTP 409. Kanal und Akteur
  setzt das Backend. `traceparent` wird mitgeschickt (`data_manager/frontend/README.md`).

### 5.2 Stammdaten: `002_governance_model.sql` + `dm-sync-governance`

Beim Deploy schreibt `dm-sync-governance` idempotent in einer Transaktion:

| Tabelle | Inhalt | Quelle |
|---|---|---|
| `app_release` | Releases (version, released_at, notes) | `workflows.RELEASES` (Code) |
| `workflow_transition` | Status-Maschine **des aktuellen Release**; ältere Releases bleiben stehen und bilden so die Historie | `workflows.py` (Code) |
| `process_catalog` | Prozess, Owner, Beschreibung | `governance_model.json` |
| `process_model_version` | Version, Genehmiger, Datum, `is_current` (genau eine) | `governance_model.json` |
| `process_model_activity` | je Version: Aktivität, `step_order`, `is_terminal`, `is_control` | `governance_model.json` |
| `process_model_transition` | je Version: erlaubte Übergänge inkl. `▶ Start` / `■ Ende` | `governance_model.json` |
| `governance_rule` | je Version: `sod` (a und b nicht dieselbe Person) bzw. `sla` (a → b ≤ `max_hours`), Schwere | `governance_model.json` |

* **Soll-Modell-Versionen sind unveränderlich.** Eine neue `model_version` im JSON legt eine neue
  Version an und markiert sie als aktuell. Die Rolle `dm_governance_sync` darf Soll-Tabellen nicht
  löschen (getestet).
* **Trennung:** Der Soll-Prozess (`governance_model.json`, Eigentum der Governance) wird **nie** aus
  dem Code erzeugt. Die Status-Maschine (`workflows.py`) gehört der Entwicklung.

### 5.3 CI-Check vor jedem Release

`pytest` → `dm-export-workflow` → `dm-check-workflow` vergleicht Status-Maschine und Soll ohne
Event-Daten:
- `SYSTEM_ERLAUBT_MEHR`: kritisch, wenn eine Kontrolle umgangen wird,
- `SOLL_NICHT_UMGESETZT`: hoch,
- `UNBEKANNTE_AKTIVITAET`: mittel.

Genehmigte Ausnahmen stehen in `accepted_deviations.json` (Begründung, Genehmiger, **Ablaufdatum**;
abgelaufene blockieren wieder). Exit-Code 1 bei offenen kritischen Befunden.

---

## 6. Databricks: Data Product `process_monitoring` (Teil 2)

### 6.1 Einbindung über Unity Catalog

`setup/01_unity_catalog_connection.sql`, einmalig durch einen Admin:
- `CREATE CONNECTION dm_postgres TYPE postgresql` mit Secrets,
- `CREATE FOREIGN CATALOG dm_pg`,
- Grants für den Job-Service-Principal.

Das dbt-Projekt liest `dm_pg.governance.*` als Quellen (`models/01_staging/_sources.yml`, var `dm_catalog`).

### 6.2 dbt-Projekt: Ordnerkonvention und Schichten

Das Projekt folgt der Konvention des Auftraggebers für Data-Product-dbt-Projekte:

| Ordner | Zweck | Modelle | Materialisierung, Zugriff |
|---|---|---|---|
| `models/01_staging/` | Aufbereitung der Quellen (1:1, Typen, aktuelle Modell-Version); `_sources.yml` | `stg_dm__process_event` (**inkrementell, MERGE auf `event_id`, Überlappungsfenster `recorded_at` − 15 Min.**), `stg_dm__app_release`, `stg_dm__workflow_transition`, `stg_dm__process_catalog`, `stg_dm__process_model_activity` / `_transition`, `stg_dm__governance_rule` | view bzw. incremental · `protected` |
| `models/02_intermediate/` | Zwischenberechnungen und Muster | `int_event_log`, `int_system_allowed_transitions`, `int_transition_classes`, `int_transitions`, `int_rule_violations`, `int_findings`, `int_case_conformance`, `int_system_conformance`, `int_rejected_attempts` | table · `protected` |
| `models/03_product/` | **ausschließlich** die Modelle des **Data Contracts**: konsumierbare Tabellen des Data Products | `mart_case_conformance`, `mart_findings`, `mart_findings_summary`, `mart_system_conformance`, `mart_rejected_attempts`, `mart_process_graph`, `mart_alert_critical_findings` | table · `public` · **erzwungener dbt-Contract** |
| `sample_data/` (außerhalb von `models/`) | Beispieldaten anstelle der 8 Quelltabellen, nur mit `--vars '{use_sample_data: true}'` | `sample__*` | table |
| `seeds/` | Konfiguration des Data Products | `finding_severity` (Schwere, Maßnahme je Befund-Typ), `process_graph_layout` (Position je Aktivität) | – |

**Data Contract (`models/03_product/_product.yml`):**
- Jedes Product-Modell hat eine explizite Spaltenliste (kein `SELECT *`).
- Datentypen sind stabil (z. B. `decimal(5,1)` für Prozentwerte), jede Spalte ist beschrieben.
- `contract: enforced` gilt: Weichen Name, Typ oder Spaltenanzahl ab, scheitert `dbt build`. Das ist
  getestet, ein falscher Typ bricht den Build ab.
- 114 Spalten in 7 Modellen. Diese Definition ist die Vorlage für die Data Contracts, die im Data
  Manager registriert werden.
- **Konsumenten lesen nur aus `03_product`.** Das gilt auch für Dashboards und den Alarm.
  Staging- und Intermediate-Modelle sind kein Teil der Schnittstelle und dürfen sich ändern.

Die Quelle wechselt das Makro `dm_source()`: mit Beispieldaten `ref('sample__…')`, sonst
`source('data_manager', …)`.

**Warum das Überlappungsfenster:** Bei parallelen Transaktionen kann eine kleinere `seq` später
committen. Eine Kopie „`seq` > Maximum“ verliert dann Zeilen. Belegt durch
`test_watermark_overlap_catches_late_commit` gegen PostgreSQL. Voraussetzung: Keine Transaktion im
Data Manager dauert länger als 15 Minuten (`var overlap_minutes`).

### 6.3 Regeln

**Übergänge** (`int_transitions`): Je Vorgang wird nach `event_ts, step_no` sortiert, nur
`event_type = 'transition'`. Daraus entstehen `src → tgt` inklusive `▶ Start` → erste Aktivität und
letzte Aktivität → `■ Ende`.

Spalten: `channel`, `app_version`, `actor` (vom Ziel-Event), `wait_h`, außerdem `is_system_allowed`
(Übergang zum Zeitpunkt laut `int_system_allowed_transitions` erlaubt).

**Klassifizierung** (`int_transition_classes`, identisch zu `conformance.classify()` in Python). Der
erste Treffer gewinnt:

| # | Bedingung | Befund-Typ | Schwere (Seed) |
|---|---|---|---|
| 0 | Übergang im Soll | – (erlaubt) | – |
| 1 | src oder tgt nicht im Soll | Zusätzliche Aktivität | mittel |
| 2 | tgt = `■ Ende` | Kein gültiger Abschluss | hoch |
| 3 | tgt ist Ende-Aktivität | Abbruch an unzulässiger Stelle | hoch |
| 4 | `step_order(tgt) <= step_order(src)` | Rücksprung / Wiederholung | mittel |
| 5 | übersprungene Kontrollschritte | **Kontrolle umgangen** | **kritisch** |
| 6 | Sprung über mindestens einen Schritt | Schritt übersprungen | hoch |
| 7 | sonst | Unzulässiger Übergang | hoch |

**Historie der Status-Maschine** (`int_system_allowed_transitions`): Gaps and Islands über die
Releases. Ein Übergang ist ab dem ersten Release einer zusammenhängenden Folge gültig
(`valid_from` = `released_at`), bis zum ersten Release ohne ihn (`valid_to`; NULL = aktuell).

**Regeln** (`int_rule_violations`): Je Vorgang zählt das erste Vorkommen jeder Aktivität.
- `sod`: Person(a) = Person(b) → Funktionstrennung verletzt.
- `sla`: Dauer(a → b) > `max_hours` → Frist überschritten.

**Befunde** (`int_findings`):

| Typ | Text in `finding` |
|---|---|
| Kontrolle umgangen | `„<Kontrollen> umgangen“` |
| Zusätzliche Aktivität | `„Zusätzlicher Schritt: …“` |
| Rücksprung | `„Rücksprung: a → b“` |
| Regelverstoß | Beschreibung der Regel |

Der Rückweg aus einer Zusatz-Aktivität wird nicht doppelt gezählt. Weitere Spalten: `channel`,
`app_version`, `system_status` (vom System erlaubt / außerhalb des Workflows).

**Vorgänge** (`int_case_conformance`):

| Spalte | Bedeutung |
|---|---|
| `is_conformant` | Pfad komplett laut Soll |
| `is_compliant` | zusätzlich kein Regelverstoß |
| `has_critical`, `has_control_bypass`, `has_sod_violation`, `has_sla_breach`, `has_outside_workflow` | Flags je Befund-Art |
| `findings` | Liste der Befunde |
| `initiator`, `start_channel`, `throughput_days` | Kontext des Vorgangs |

**System-Konformität** (`int_system_conformance`) je Übergang aus Soll ∪ System ∪ Ist. Der erste
Treffer gewinnt:

| # | Kategorie | Schwere |
|---|---|---|
| 1 | Umgehung außerhalb des Workflows (beobachtet, zum Zeitpunkt nicht vom System erlaubt) | kritisch |
| 2 | Soll-Schritt nicht implementiert | hoch |
| 3 | System lässt mehr zu – genutzt | kritisch bei Kontrolle umgangen, sonst mittel |
| 4 | System lässt mehr zu – latent (nie beobachtet) | hoch bei Kontrolle umgangen, sonst mittel |
| 5 | Nicht mehr erlaubt (früher im System) | info |
| 6 | Vom System abgewiesen (nur abgewiesene Versuche) | info |
| 7 | Konform | – |

Bewusste Abstufung: Eine latente Lücke ist im Monitoring „hoch“, im CI-Check „kritisch“ (blockiert
das Release).

**Befund-Übersicht** (`mart_findings_summary`) je `process`, `domain_scope` (`'Alle'` oder eine
Domäne), Befund:
- `cases`, `pct_of_cases`,
- `cases_last_4w`, `pct_last_4w` (Vorgänge mit Start in den letzten 28 Tagen ab jüngstem Start),
- `first_seen`, `last_seen`,
- `status`: `neu`, wenn das erste Vorkommen in den letzten 56 Tagen liegt; sonst `tritt weiterhin
  auf`, wenn eines in den letzten 28 Tagen liegt; sonst `nicht mehr aufgetreten`,
- `channels`, `first_release`, `system_status`, `recommended_action`, `process_owner`.

**Alarm** (`mart_alert_critical_findings`): kritische Befunde mit Vorkommen in den letzten 7 Tagen
oder neu (56 Tage). Dazu `example_cases`, `channels`, `system_status` und `process_owner`.

### 6.4 Prozessgraph: `mart_process_graph` + `process_graph.vl.json`

Je `process` und `domain_scope` wird eine Ergebnismenge mit folgenden Zeilentypen berechnet:
- `node` (x, y, w, h; Aktivität 180 × 44, Start/Ende 28 × 28; `is_control`),
- `edge` (Stützpunkte, `seq`),
- `arrow` (`shape`),
- `label`,
- `frame` (Zeichenbereich 800 × Höhe).

Weitere Spalten: `conformance` (soll/abweichung/kontrolle_umgangen/latent) und `system_status`.

**Kantenverlauf** (rechtwinklig; der Typ wird in dieser Reihenfolge bestimmt):

| Typ | Verlauf |
|---|---|
| `self` | Schleife oben rechts |
| `down_across` | Ziel = Ende: am äußeren Rand der Quelle (x0 ± (w0/2 − 8)) nach unten, dann seitlich in den Kreis |
| `skip` | senkrecht, aber ein Kasten liegt dazwischen: links raus; Spur `min(linker Rand) − 25 − 14·r`; runter bis `y1 − h1/2 − 10 − 8·rt`; zum Eingang; oben hinein |
| `straight` | senkrecht |
| `side_down` | aus der Seitenkante, waagrecht, oben hinein |
| `same_row` | waagrecht; nach rechts 11 über, nach links 11 unter der Mitte |
| `back` | rechts raus (y0 − 8), Spur `max(rechter Rand) + 25 + 14·r`, hoch, rechts hinein (y1 + 8) |

**Verteilung:**
- **Eingänge oben am Ziel:** Gruppen skip (−1, lange zuerst), links (0, y0 absteigend), senkrecht
  (1), rechts (2, y0 aufsteigend); Abstand ±min(w1/2 − 20, 25·(n − 1)).
- **Seitliche Ausgänge:** entferntere Ziele weiter oben; ±min(h0/2 − 8, 8·(n − 1)).
- **Seitliche Eingänge in den End-Kreis:** ±5.

**Latente Kanten** (System erlaubt, Soll nicht, insgesamt nie genutzt) werden dünn und grau
gepunktet gezeichnet, ohne Zahl.

**Vega-Lite:**
- `data.name = "databricks_query"`, Breite und Höhe `container`, Skalen ohne feste Domain (die
  `frame`-Zeilen bestimmen die Ausdehnung).
- Ebenen:
  - Kanten: Farbe und Strich nach `conformance`: grau `#8f8e88`, orange `#eb6834` gestrichelt, rot
    `#d03b3b` gestrichelt, latent `#a3a29c` gepunktet.
  - Pfeile.
  - Beschriftungs-Pillen (nur bei `cases > 0`) mit Tooltip: Von, Nach, Befund, System, Übergänge,
    Median-Wartezeit.
  - Kästen soll und abweichung. Die Abweichungs-Ebene enthält zusätzlich die `frame`-Zeilen, damit
    sie nie leer ist.
  - Text und „◆ KONTROLLE“.
  - Start- und End-Kreise.
- Muss in Vega-Lite 5 und 6 ohne Warnungen kompilieren.

**Felder der Custom Viz** (ohne Aggregation): `process, domain_scope, row_type, id, src, tgt, cases,
median_wait_h, x, y, w, h, seq, shape, node_kind, conformance, is_control, finding_type, system_status`.

---

## 7. Dashboard (3 Seiten) und Jobs

Zielbilder: `mockup/dashboard_preview.png`, `mockup/dashboard_detail_preview.png` und
`mockup/dashboard_system_preview.png`. Interaktiv: `mockup/dashboard.html`.

**Datasets** sind ausschließlich `SELECT * FROM mart_*`, ohne Parameter. Katalog und Schema kommen
je Target aus dem Bundle. Gefiltert wird über die Felder `process`, `domain` bzw. `domain_scope`
(Standard `'Alle'`).

**Seite „Übersicht“:**
- Filter.
- Banner bei neuem kritischem Befund.
- Sechs Zähler: Vorgänge, Prozesskonformität, Governance-konform, Vorgänge mit kritischem Befund,
  aktive kritische Befunde, neue Befunde.
- Je Prozess eine Karte: Owner, Rate, Mini-Verlauf, Kennzahlen, wichtigster Befund; ein Klick
  öffnet die Detailseite.
- Konformität je Startmonat (eine Linie je Prozess, nur volle Monate, Ziel, Ereignis).
- Vorgänge je Prozess und Befund-Typ.
- Tabelle „Handlungsbedarf“: Schwere, Status, Prozess, Befund mit Meta-Zeile (Typ · Kanal · seit
  Release · System-Status), letzte 4 Wochen, gesamt, erstmals, verantwortlich, Maßnahme.
- Tabelle „Nicht mehr aufgetreten“.

**Seite „Prozessdetail“:**
- Prozess-Auswahl (Filter auf `process` in allen Datasets inklusive `mart_process_graph`).
- Zähler: Vorgänge, Konformität, Kontrolle umgangen, Funktionstrennung, Frist, Ø Durchlaufzeit.
- Prozessgraph (Custom Viz).
- Konformität je Woche, Befund-Typen.
- Befund-Tabelle, betroffene Vorgänge.

**Seite „System-Konformität“:**
- Zähler: Übergänge System/Soll, System lässt mehr zu (genutzt/latent), Soll nicht implementiert,
  außerhalb des Workflows, abgewiesene Versuche, CI-Ergebnis.
- Tabelle „Soll · System · Ist je Übergang“.
- Vorgänge nach Kanal, abgewiesene Versuche.
- Release-Zeitleiste mit Wirkung und CI-Ergebnis. Das CI-Ergebnis ist der JSON-Bericht von
  `dm-check-workflow`; der Data Manager kann ihn optional als Tabelle bereitstellen.

Schwere und Status immer mit Icon und Text, nie nur über Farbe.

**Job `process_monitoring_refresh`** (`resources/process_monitoring.job.yml`), alle 15 Minuten:
1. `dbt_task`: `dbt deps` und `dbt build --target databricks --vars '{dm_catalog: …}'`, auf dem
   SQL Warehouse, Umgebung mit `dbt-databricks`.
2. `alert_critical_findings` (SQL-Task): schlägt fehl, wenn `mart_alert_critical_findings` Zeilen
   hat. Dann geht eine E-Mail an `var.alert_emails`.

Alternative: ein Databricks SQL Alert direkt auf dem Mart.

**Dashboard-Ressource** (`resources/process_monitoring.dashboard.yml`): `file_path` auf das
`.lvdash.json`, `dataset_catalog` und `dataset_schema` je Target (im Workspace prüfen). Nach dem
Einrichten der Custom Viz exportieren: `databricks bundle generate dashboard --existing-id …`.

---

## 8. Umsetzungsschritte

Siehe [`AGENTS.md`](AGENTS.md), Arbeitspakete AP1–AP10, jeweils mit Prüfung.

---

## 9. Abnahmewerte (Beispieldaten, `use_sample_data: true`)

Als dbt-Tests implementiert (`process_monitoring/dbt/tests/acceptance_*.sql`). `dbt build` schlägt
fehl, wenn ein Wert abweicht.

| Prüfung | Erwartet |
|---|---|
| Vorgänge | 1.000 (AR 500, DC 300, DP 200) |
| Prozesskonformität | gesamt 74,5 % · AR 72,0 · DC 78,3 · DP 75,0 |
| Governance-konform | gesamt 68,5 % · AR 63,6 · DC 74,3 · DP 72,0 |
| kritisch / Kontrolle umgangen / Funktionstrennung / Frist | gesamt 251 / 220 / 39 / 49 · AR 123/105/23/42 · DC 73/65/10/6 · DP 55/50/6/1 |
| AR Konformität je Monat | Jan 90,0 · Apr 60,6 · Jun 58,9 |
| `mart_findings_summary` (Alle) | 14 Zeilen; 7 aktive kritische; 1 neu: DP „Data Contract verknüpft, Qualitätsprüfung, Freigabe Data Owner umgangen“ (10, erstmals 21.05.2026); AR „Prüfung Security umgangen“: 90, 02.04.2026, 29,2 %, tritt weiterhin auf, Kanal system, seit 2.3, vom System erlaubt; DC „Schema validiert umgangen“: 25, zuletzt 30.03.2026, nicht mehr aufgetreten; 5 domain_scopes |
| `mart_system_conformance` | 42 Übergänge, 31 konform; System 38 / Soll 32; außerhalb: AR ▶ Start → Berechtigung erteilt, DP Angelegt → Veröffentlicht; latent: AR Beantragt → Berechtigung erteilt, DP Metadaten erfasst → Freigabe Data Owner; nicht implementiert: DC Review Änderung → Verworfen; 5 × genutzt |
| `mart_rejected_attempts` | 25 |
| `mart_alert_critical_findings` | 5 Zeilen, 1 neu |
| `mart_process_graph` (Alle) | Knoten AR 7 / DC 12 / DP 9; latent AR „Beantragt → Berechtigung erteilt“, DP „Metadaten erfasst → Freigabe Data Owner“; 15 Kombinationen aus Prozess und Scope |
| Data Manager | 17 pytest-Tests (6 PostgreSQL); `dm-export-workflow` = 38 Übergänge = `governance/workflow_definition.json`; `dm-check-workflow --today 2026-07-06`: 8 Befunde, 6 blockierend, Exit 1; Sync: 4 Releases, 38 Übergänge (2.5), 32 Soll-Übergänge, 6 Regeln |

---

## 10. Risiken und Fallstricke

* **Inkrementelle Übernahme:** nie „`seq` > Maximum“, sondern mit Überlappungsfenster und
  Deduplizierung (siehe 6.2).
* **Last auf PostgreSQL:** Der Foreign Catalog liest live, deshalb auf ein Read-Replica zeigen. Das
  Dashboard liest nur Delta-Marts.
* **Laufende Vorgänge** verfälschen „Kein gültiger Abschluss“ und die Konformität (Klärungspunkt 4).
* **Technische Accounts** (`system`, Service-Accounts) bei der Funktionstrennung je Regel festlegen.
* **Versionierung** (Data Contracts): Ist ein Vorgang ein Contract über alle Versionen oder eine
  Änderung? Einmal festlegen.
* **Selbstprüfung vermeiden:** Soll-Modell (Governance) und Status-Maschine (Code) bleiben getrennt.
* **Undokumentiert bzw. Preview:** Das `.lvdash.json`-Format, Custom Viz und die
  Dashboard-Felder `dataset_catalog`/`dataset_schema` im Bundle sind nicht offiziell dokumentiert
  oder noch in Preview. Den echten Export versionieren.
* **dbt lokal vs. Databricks:** Lokal läuft `dbt-spark` (Session) auf Spark 4.0.1 mit Delta 4.0.
  Produktiv läuft `dbt-databricks`. Die Modelle nutzen nur gemeinsame Spark-SQL-Funktionen und
  Konfigurationen (`file_format: delta`, `merge`). Der erste Lauf im Workspace ist trotzdem zu
  prüfen.
* **Personenbezug:** `actor` und `initiator` sind personenbezogen. Zugriff auf Foreign Catalog,
  Marts und Dashboard beschränken.

---

## 11. Lokal prüfen

`bash tools/verify_all.sh`, optional mit `DM_TEST_PG_DSN`. Die Schritte:
1. pytest des Data-Manager-Pakets,
2. CI-Check,
3. `dbt build` mit Beispieldaten (`tools/run_dbt_local.sh`, lädt die Delta-JARs beim ersten Lauf),
4. Export von `mart_process_graph` und Render-Check (`tools/check_vega_spec.mjs`).

Benötigte Pakete:
- Python: `pytest`, `psycopg[binary]`, `dbt-core>=1.10`, `dbt-spark[session]>=1.9`, `pyspark==4.0.1`,
- außerdem Java 17+ und Node 18+ (`cd tools && npm install`).
