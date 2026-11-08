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
3. **Genau ein Event je Statuswechsel**, in **derselben Transaktion** wie die Statusänderung
   (Outbox-Pattern). Kein Event ohne Statuswechsel, kein Statuswechsel ohne Event.
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

Beispiele: [`examples/events_example.jsonl`](examples/events_example.jsonl).

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
| Uhrzeit | UTC, Millisekunden; bei gleichem Zeitstempel entscheidet die Reihenfolge der Outbox |

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
* Vollständiges Beispiel: [`config/workflow_definition.json`](config/workflow_definition.json)

## 6. Datenfluss

```
Data Manager  ── transition() ──►  DB (Status + Outbox, 1 Transaktion)
                                        │
                                        ▼  Outbox-Publisher (Job/CDC)
                                Databricks Bronze (Events roh, JSON)
                                        │  Dedupe nach event_id, Typen
                                        ▼
                     main.data_manager_pm.event_log  (Silver, Spalten wie oben)
                                        │
                     Views 03_views.sql ─► Dashboard, SQL Alerts

Build/Release ── export ──► workflow_definition.json ──► CI-Check gegen governance_model.json
                                                    └──► 11_load_config_from_json.sql (Historie)
```

## 7. Referenz-Implementierung

[`examples/event_writer_example.py`](examples/event_writer_example.py) zeigt:
- die zentrale Status-Maschine,
- `transition()` mit Outbox und Protokollierung abgewiesener Versuche,
- den Export der Workflow-Definition.

Das Beispiel ist in Python geschrieben und lässt sich 1:1 auf andere Sprachen übertragen.

## 8. Checkliste für Entwickler

- [ ] Alle Statusänderungen laufen durch `transition()`, auch in Batch, Migration und Admin.
- [ ] Event und Statusänderung stehen in derselben Transaktion (Outbox).
- [ ] Abgewiesene Übergänge erzeugen ein `rejected`-Event.
- [ ] `channel`, `app_version` und `actor` sind immer gefüllt; Service-Accounts sind erkennbar.
- [ ] `workflow_definition.json` wird im Build erzeugt, und der CI-Check läuft vor jedem Release.
- [ ] Neue Übergänge, die eine Kontrolle umgehen, brauchen eine genehmigte Ausnahme
      (`accepted_deviations.json`) oder eine Anpassung des Soll-Prozesses durch die Governance.
