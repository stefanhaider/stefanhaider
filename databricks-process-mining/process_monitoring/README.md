# Teil 2: Databricks Asset Bundle `process_monitoring`

Eigenständiges Databricks-Projekt für das Prozess- und Governance-Monitoring des Data Managers.
Es läuft **unabhängig** von der Applikation. Die einzige Verbindung sind deren Daten, per Unity
Catalog als Foreign Catalog eingebunden.

**Data Product = dbt-Projekt** (`dbt/`). Daraus entstehen die Marts für das Dashboard und den Alarm.

```
dm_pg.governance.*  (Foreign Catalog, read-only)
   └─ dbt: 01_staging → 02_intermediate → 03_product (Data Contract, mart_*)
        ├─ Dashboard "Data Manager – Prozess- & Governance-Monitoring" (3 Seiten)
        └─ Alarm-Task (kritische Befunde → E-Mail)
Job process_monitoring_refresh: alle 15 Minuten  dbt build → Alarm
```

## Inhalt

| Pfad | Inhalt |
|---|---|
| `databricks.yml` | Bundle, Variablen (`catalog`, `schema`, `dm_catalog`, `warehouse_id`, `use_sample_data`, `alert_emails`), Targets `dev`/`prod` |
| `resources/process_monitoring.job.yml` | Job: `dbt_task` (dbt-databricks auf dem SQL Warehouse) und Alarm-SQL-Task |
| `resources/process_monitoring.dashboard.yml` | Dashboard-Ressource |
| `setup/01_unity_catalog_connection.sql` | **einmalig (Admin):** Connection auf PostgreSQL, Foreign Catalog `dm_pg`, Grants, Vollständigkeitskontrolle |
| `dbt/` | Data Product: `models/01_staging`, `02_intermediate`, `03_product` (**nur** Data-Contract-Modelle, erzwungene Contracts), `sample_data/` (Beispieldaten), `seeds/`, `tests/`, `macros/`; Konventionen in [`dbt/README.md`](dbt/README.md) |
| `src/dashboards/process_monitoring.lvdash.json` | Dashboard-Entwurf (nach Einrichtung durch Export ersetzen) |
| `src/dashboards/process_graph.vl.json` | Vega-Lite-Spezifikation des Soll-Ist-Prozessgraphen (Custom Viz) |
| `src/sql/alert_critical_findings.sql` | Alarm-Task |

## Nutzung

```bash
# einmalig: setup/01_unity_catalog_connection.sql durch einen Admin ausführen
databricks bundle validate -t dev
databricks bundle deploy   -t dev
databricks bundle run      -t dev process_monitoring_refresh

# lokal (ohne Workspace): Data Product mit Beispieldaten bauen und testen
bash ../tools/run_dbt_local.sh
```

In `dev` ist `use_sample_data: true` voreingestellt. Das Data Product läuft dann mit den eingebauten
Beispieldaten, bis der Foreign Catalog steht. Danach auf `false` setzen.

Stand: `dbt build` lokal 50/50 grün (inklusive Abnahmetests und inkrementellem zweitem Lauf).
Bundle-Deploy, Job, Dashboard und Custom Viz sind im Workspace **noch ungetestet**.
