# Teil 1: Data Manager – Daten fürs Prozess-Monitoring erzeugen

Der Data Manager (Python-Backend, Vue-Frontend, PostgreSQL) erzeugt **alle Daten**, die das
Databricks-Data-Product `process_monitoring` braucht. Databricks liest sie read-only per Unity
Catalog. Es gibt keine weitere Schnittstelle.

| Was | Wo | Wann |
|---|---|---|
| Footprints jedes Statuswechsels (inkl. abgewiesener Versuche) | `governance.process_event` (append-only) | bei jedem `StateMachine.transition()`, gleiche Transaktion |
| Releases und Status-Maschine je Release | `governance.app_release`, `governance.workflow_transition` | beim Deploy: `dm-sync-governance` |
| Soll-Prozesse, Kontrollschritte, Regeln, Process Owner | `governance.process_model_*`, `governance_rule`, `process_catalog` | beim Deploy aus `governance/governance_model.json` |

## Inhalt

| Pfad | Inhalt |
|---|---|
| `python/` | Paket `datamanager_governance` (`pip install ./python[test]`), 17 Tests |
| `python/sql/postgres/001_process_event.sql` | Footprint-Tabelle, Append-only-Trigger, Rollen `dm_event_writer` / `dm_event_reader` |
| `python/sql/postgres/002_governance_model.sql` | Stammdaten-Tabellen, Rolle `dm_governance_sync` |
| `governance/governance_model.json` | **Soll-Modell (Eigentum der Governance, CODEOWNERS)**, nie aus dem Code erzeugen |
| `governance/accepted_deviations.json` | genehmigte Abweichungen (Begründung, Genehmiger, Ablaufdatum) |
| `governance/workflow_definition.json` | Export der Status-Maschine (`dm-export-workflow`), für Reviews und CI |
| `frontend/` | Vue-3-Bausteine und Regeln: UI zeigt nur erlaubte Aktionen, 409 bei Abweisung, `traceparent` |
| `ci/` | CI-Wrapper und Pipeline-Beispiel (inkl. PostgreSQL-Service für die Tests) |
| `examples/` | lauffähige Demo, Beispiel-Events |

## Kommandos

```bash
pip install ./python[test]
pytest python/tests                                   # mit DM_TEST_PG_DSN=... auch gegen PostgreSQL
dm-export-workflow --out build/workflow_definition.json
dm-check-workflow --model governance/governance_model.json --workflow build/workflow_definition.json \
                  --accepted governance/accepted_deviations.json          # Exit 1 = Release blockiert
dm-sync-governance --dsn "$DATABASE_URL" --model governance/governance_model.json   # beim Deploy
```

Details: [`../EVENT_STANDARD.md`](../EVENT_STANDARD.md), [`../IMPLEMENTATION_SPEC.md`](../IMPLEMENTATION_SPEC.md) Abschnitt 5.
