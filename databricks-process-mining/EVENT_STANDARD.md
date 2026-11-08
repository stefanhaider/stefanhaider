# Event-Standard für den Data Manager

> Verbindliches Format für Prozess-Events des Data Managers. Diese Events sind die Grundlage
> für das Prozess- und Governance-Monitoring. Weil der Data Manager selbst entwickelt wird,
> werden sie **direkt an der Quelle** sauber erzeugt, statt sie aus technischen Logs zu
> rekonstruieren.

## 1. Grundsätze

1. **Eine zentrale Status-Maschine je Objekttyp.** Erlaubte Übergänge sind an genau einer
   Stelle im Code definiert. Keine Statusänderung „nebenbei“ in Services, Jobs oder Skripten.
2. **Jeder Statuswechsel läuft durch denselben Code-Pfad** (`transition()`), unabhängig vom
   Kanal: UI, REST-API, Admin-API, Batch, Migration oder System-Automatik.
3. **Genau ein Event je Statuswechsel**, in **derselben Transaktion** wie die Statusänderung, in
   die append-only Tabelle `governance.process_event` der PostgreSQL-Datenbank des Data Managers.
   Kein Event ohne Statuswechsel, kein Statuswechsel ohne Event. Die Tabelle ist der dauerhafte
   Audit-Trail. Databricks liest sie über Unity Catalog (Lakehouse Federation); ein eigener
   Versand-Job entfällt.
4. **Abgewiesene Versuche werden ebenfalls protokolliert** (`event_type = 'rejected'`). Sie
   belegen, dass Kontrollen greifen, und zeigen, wo Anwender Umgehungen versuchen.
5. **Die Status-Maschine ist exportierbar** (`workflow_definition.json`), damit sie vor jedem
   Release gegen den Soll-Prozess geprüft werden kann (CI-Check).
6. **Soll-Prozess und Status-Maschine bleiben getrennt.** Der Soll-Prozess
   (`governance_model.json`) gehört der Governance bzw. den Process Ownern und wird **nicht**
   aus dem Code erzeugt. Sonst prüft das System nur gegen sich selbst.

## 2. Felder

| Feld | Typ | Pflicht | Beschreibung |
|---|---|---|---|
| `event_id` | UUID | ja | eindeutige ID, für Deduplizierung |
| `event_type` | STRING | ja | `transition` (Status geändert) oder `rejected` (Versuch abgewiesen) |
| `process` | STRING | ja | Objekttyp/Prozess, z. B. `Access Request`, `Data Contract`, `Data Product`, `Change Approval` |
| `case_id` | STRING | ja | fachliche ID des Vorgangs (Antrag, Contract, Produkt). Bei Versionierung siehe 4 |
| `object_version` | STRING | nein | Version des Objekts, z. B. Contract-Version |
| `domain` | STRING | ja | Datendomäne bzw. Owner-Team (Filter, Zuständigkeit) |
| `from_activity` | STRING | ja* | Status vorher; `null` bei Anlage. *Bei `rejected` immer gefüllt |
| `activity` | STRING | ja | Status nachher bzw. bei `rejected` der versuchte Zielstatus |
| `actor` | STRING | ja | ausführende Person bzw. technischer Account (`system`, `svc_…`) |
| `channel` | STRING | ja | `ui`, `api`, `admin_api`, `batch`, `migration`, `system` |
| `app_version` | STRING | ja | Release des Data Managers |
| `workflow_version` | STRING | ja | Version der Status-Maschine (oft gleich `app_version`) |
| `trace_id` | STRING | empfohlen | Korrelation mit Application Monitoring (OpenTelemetry Trace-ID) |
| `event_ts` | TIMESTAMP (UTC, ms) | ja | Zeitpunkt der Statusänderung |
| `reason` | STRING | nein | Begründung, z. B. Genehmigungskommentar oder Abweisungsgrund |

Beispiele: [`data_manager/examples/events_example.jsonl`](data_manager/examples/events_example.jsonl).

## 3. Benennung der Aktivitäten

* `activity` verwendet die **fachlichen Namen aus dem Soll-Prozess** (z. B. „Prüfung Data
  Owner“), nicht technische Statuscodes. Das Mapping Code → Name steht in der Status-Maschine.
* Pro Prozess eindeutige Namen. Gleicher Schritt = gleicher Name, auch über Kanäle hinweg.
* Technische Zwischenschritte (z. B. „Benachrichtigung versendet“) sind **keine** Prozess-Events.

## 4. Sonderfälle

| Fall | Regel |
|---|---|
| Versionierte Objekte (Data Contracts) | `case_id` = Contract-ID, `object_version` = Version. Änderungszyklen sind eigene Aktivitäten (Änderung beantragt → …). Alternativ eine Änderung als eigener Vorgang (`case_id` = Änderungs-ID). Wichtig ist, das einmal festzulegen |
| Batch und Migration | gleicher Code-Pfad, `channel = batch/migration`, `actor` = Service-Account. Darf die Status-Maschine nicht umgehen. Falls doch nötig: eigener, erlaubter Übergang mit Kanal-Einschränkung |
| Admin-Korrekturen | `channel = admin_api`, Pflichtfeld `reason`. Erlaubte Admin-Übergänge explizit in der Status-Maschine |
| Wiederholte Events | gleiche `event_id` wird beim Laden dedupliziert |
| Uhrzeit | UTC, Millisekunden; bei gleichem Zeitstempel entscheidet `seq` aus `process_event` |

## 5. Status-Maschine exportieren: `workflow_definition.json`

```json
{
  "application": "Data Manager",
  "release": "2.5",
  "exported_at": "2026-07-06T00:00:00Z",
  "workflows": [
    { "process": "Access Request",
      "transitions": [
        { "from": "▶ Start", "to": "Beantragt", "since_release": "2.2", "note": "Standard-Workflow" },
        { "from": "Prüfung Data Owner", "to": "Berechtigung erteilt", "since_release": "2.3",
          "note": "Security-Prüfung optional (interne Daten)", "channels": ["ui", "system"] }
      ] }
  ]
}
```

* `▶ Start` = Anlage, `■ Ende` = Abschluss (Übergänge von Ende-Status nach `■ Ende` mit exportieren)
* optional `channels`: Übergang nur über bestimmte Kanäle erlaubt
* Vollständiges Beispiel: [`data_manager/governance/workflow_definition.json`](data_manager/governance/workflow_definition.json)

## 6. Datenfluss

```
Data Manager ── transition() ──► PostgreSQL: Status + governance.process_event (1 Transaktion, append-only)
                                        │  Unity Catalog: Connection + Foreign Catalog dm_pg
                                        │  (read-only User, möglichst Read-Replica)
                                        ▼  Databricks Asset Bundle process_monitoring
                     dbt (Data Product): stg_dm__process_event (inkrementell, MERGE alle 15 Min.)
                                        ▼
                     int_* → mart_*  → Dashboard, Alarm
                                        │
                     

Build/Release ── dm-export-workflow ──► workflow_definition.json ──► dm-check-workflow gegen governance_model.json
Deploy        ── dm-sync-governance ──► governance.app_release / workflow_transition / process_model_* / governance_rule
```

## 7. Umsetzung in Python: Paket `datamanager_governance`

Der Data Manager ist in Python geschrieben. Deshalb liegt die Umsetzung als installierbares Paket
in [`data_manager/python/`](data_manager/python) vor (`pip install ./python`). Der Kern braucht nur die Standardbibliothek,
für PostgreSQL wird `psycopg` 3 verwendet. Es gibt 17 Tests, davon 6 gegen echtes PostgreSQL 16
(laufen mit `DM_TEST_PG_DSN`).

| Modul | Inhalt |
|---|---|
| `events.py` | `ProcessEvent` (Dataclass) mit Validierung der Pflichtfelder, Kanäle und Event-Typen; `to_json()` |
| `state_machine.py` | `Workflow` (erlaubte Übergänge inkl. Kanal-Einschränkung, Endzustände), `StateMachine.transition()`: einziger Weg für Statuswechsel, schreibt das Event in `process_event` (gleiche Transaktion), wirft `TransitionRejected` |
| `event_store.py` | `PostgresEventStore` (psycopg) bzw. `SqliteEventStore` (Tests) für `process_event`, `autonomous_sink()` für abgewiesene Versuche in eigener Transaktion, Beispiele für SQLAlchemy und Django |
| `data_manager/python/sql/postgres/001_process_event.sql` | PostgreSQL-DDL: Tabelle mit Spalten nach Standard, Prüfung auf UTF-8, **Append-only-Trigger** (UPDATE/DELETE/TRUNCATE verboten), Rollen `dm_event_writer` (nur INSERT) und `dm_event_reader` (nur SELECT, für Databricks) |
| `workflows.py` | **die Status-Maschinen des Data Managers** (Access Request, Data Contract, Data Product): Single Source of Truth der System-Ebene |
| `export.py` | `dm-export-workflow`: erzeugt `workflow_definition.json` |
| `conformance.py` | `dm-check-workflow`: CI-Check gegen den Soll-Prozess |
| `governance_sync.py` | `dm-sync-governance`: schreibt beim Deploy Releases, Status-Maschine des aktuellen Release, Soll-Modell (versioniert, unveränderlich), Regeln und Owner nach `governance.*` (DDL: `002_governance_model.sql`) |

**Einbindung:**

```python
from datamanager_governance.state_machine import StateMachine, TransitionRejected
from datamanager_governance.workflows import WORKFLOWS, APP_VERSION

sm = StateMachine(WORKFLOWS, store=ObjectRepository(), events=SqlAlchemyEventStore(),
                  app_version=APP_VERSION, reject_sink=reject_in_own_transaction)

# Service-Schicht, z. B. FastAPI-Endpoint oder Django-View – NIE den Status direkt setzen:
with session.begin():                                    # Django: with transaction.atomic():
    sm.transition("Access Request", req_id, "Prüfung Data Owner",
                  actor=current_user.id, channel="ui", conn=session, domain=req.domain,
                  trace_id=current_trace_id(), reason=comment)
```

* **Abgewiesene Versuche** gehen über `reject_sink` in einer **eigenen** Transaktion. Sonst
  verschwinden sie mit dem Rollback, den `TransitionRejected` in der Anwendung auslöst.
* **Keine Statusänderung außerhalb von `transition()`.** Kein direktes `obj.status = ...` und
  keine Massen-Updates per SQL. Am besten das Statusfeld im ORM schreibgeschützt machen und
  per Code-Review bzw. Lint-Regel absichern.
* Batch- und Migrationsjobs rufen ebenfalls `transition()` auf, mit `channel="batch"` bzw.
  `"migration"` und einem Service-Account als `actor`.
* `trace_id` aus OpenTelemetry übernehmen. Dann lässt sich jedes Event mit dem Application
  Monitoring verknüpfen.
* **Vue-Frontend:** Die UI zeigt nur Aktionen aus `StateMachine.allowed_next()`, behandelt HTTP 409
  bei Abweisung und schickt `traceparent` mit. Bausteine und Regeln:
  [`data_manager/frontend/`](data_manager/frontend).
* Lauffähige Demo: [`data_manager/examples/event_writer_example.py`](data_manager/examples/event_writer_example.py).

## 8. Checkliste für Entwickler

- [ ] Alle Statusänderungen laufen durch `transition()`, auch in Batch, Migration und Admin.
- [ ] Event und Statusänderung stehen in derselben Transaktion (`process_event`).
- [ ] `process_event` ist append-only (Trigger aktiv). Die App nutzt eine Rolle mit nur INSERT,
      Databricks eine Rolle mit nur SELECT.
- [ ] Abgewiesene Übergänge erzeugen ein `rejected`-Event.
- [ ] `channel`, `app_version` und `actor` sind immer gefüllt; Service-Accounts sind erkennbar.
- [ ] `workflow_definition.json` wird im Build erzeugt (`dm-export-workflow`), und der CI-Check
      (`dm-check-workflow`) läuft vor jedem Release.
- [ ] Abgewiesene Versuche gehen über `reject_sink` in eine eigene Transaktion.
- [ ] Neue Übergänge, die eine Kontrolle umgehen, brauchen eine genehmigte Ausnahme
      (`accepted_deviations.json`) oder eine Anpassung des Soll-Prozesses durch die Governance.
