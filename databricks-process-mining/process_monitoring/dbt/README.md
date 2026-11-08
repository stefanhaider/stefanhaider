# dbt-Projekt `process_monitoring` = Data Product

Aufbau nach der Konvention für Data-Product-dbt-Projekte:

| Ordner | Inhalt | Regeln |
|---|---|---|
| `models/01_staging/` | Aufbereitung der Quellen aus dem Data Manager (`stg_dm__*`), Quelldefinition `_sources.yml` | 1:1 zur Quelle, nur Typen, Namen, Filter auf die aktuelle Modell-Version; `stg_dm__process_event` inkrementell |
| `models/02_intermediate/` | Zwischenberechnungen und Muster (`int_*`) | frei änderbar, kein Teil der Schnittstelle |
| `models/03_product/` | **ausschließlich** Modelle des **Data Contracts** | `access: public`; explizite Spalten; stabile Datentypen; **erzwungener Contract** in `_product.yml`; nur diese Modelle werden konsumiert (Dashboards, Alarm, weitere Konsumenten) |
| `sample_data/` | Beispieldaten anstelle der Quellen (`sample__*`) | nur aktiv mit `--vars '{use_sample_data: true}'`; bewusst außerhalb von `models/` |
| `seeds/` | Konfiguration des Data Products | Schweregrade je Befund-Typ, Layout des Prozessgraphen |
| `tests/` | Abnahmetests (`acceptance_*`) | nur mit Beispieldaten aktiv; prüfen die Zahlen aus IMPLEMENTATION_SPEC.md, Abschnitt 9 |
| `macros/` | `dm_source()` (Quelle oder Beispieldaten), generischer Eindeutigkeitstest | – |

## Data Contract ändern

1. Spalte im Product-Modell **und** in `_product.yml` gleichzeitig ändern. Sonst scheitert `dbt build`.
2. Eine Änderung, die Konsumenten bricht (Spalte entfernen, umbenennen, Typ ändern), ist eine neue
   Contract-Version. Sie muss mit den Konsumenten abgestimmt und im Data Manager als neue Version
   des Data Contracts registriert werden.
3. Neue Spalten hinzufügen ist rückwärtskompatibel.

## Ausführen

```bash
# lokal mit Beispieldaten (Spark + Delta), inkl. aller Tests
bash ../../tools/run_dbt_local.sh
# im Databricks-Job (siehe ../resources/process_monitoring.job.yml)
dbt build --target databricks --vars '{dm_catalog: dm_pg, use_sample_data: false}'
```
