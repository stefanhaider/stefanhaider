# Process Mining als Sankey-Diagramm in Databricks AI/BI Dashboards (Mockup)

![Vorschau](preview.png)

Mockup eines Prozessfluss-Dashboards für **Process Mining** (Beispiel: Order-to-Cash).
Das Sankey-Diagramm zeigt, wie 1.000 Aufträge Schritt für Schritt durch den Prozess
laufen. Man sieht den Happy Path, Abkürzungen (ohne Kreditprüfung), Nacharbeit
(Preisänderung, Mahnung, Gutschrift) und Abbrüche (Storno).

## Dateien

| Datei | Inhalt |
|---|---|
| `01_sample_event_log.sql` | Erzeugt `main.process_mining.event_log` mit synthetischen Daten: 1.000 Fälle, 8 Varianten, 4 Regionen (`case_id`, `activity`, `event_ts`, …) |
| `02_sankey_dataset.sql` | Dashboard-Dataset: ein Prozesspfad pro Zeile, Spalten `step_1` … `step_7` sind die Sankey-Stufen, `cases` ist der Wert |
| `03_kpis_dataset.sql` | Dataset für die KPI-Kacheln: Fälle, Varianten, Ø Durchlaufzeit, Storno- und Nacharbeitsquote |
| `process_mining_sankey.lvdash.json` | Importierbarer Dashboard-Entwurf: Region-Filter, 6 KPI-Kacheln, Sankey, Variantentabelle |
| `mockup.html` | Interaktive Vorschau im Browser: Hover-Tooltips, Hell/Dunkel. Funktioniert ohne Databricks |

## So funktioniert die Sankey-Logik

Das Sankey-Diagramm in Databricks AI/BI arbeitet mit **Stufen-Spalten** (Stages) und einem
**Wert**. Deshalb wird jeder Fall zuerst in seine geordnete Aktivitätenfolge (Trace)
umgewandelt und dann nach Pfad gruppiert:

```sql
transform(array_sort(collect_list(struct(event_ts, step_no, activity))), x -> x.activity) AS trace
...
try_element_at(trace, 1) AS step_1, ..., try_element_at(trace, 7) AS step_7, COUNT(*) AS cases
```

* Gleiche Aktivitäten in verschiedenen Stufen sind eigene Knoten. Dadurch werden Schleifen
  sichtbar, z. B. "Auftrag freigegeben → Preisänderung → Auftrag freigegeben".
* Kürzere Pfade enden mit `NULL`, der Fluss hört dort auf.
* Bei echten Daten mit langen Traces die Anzahl der Stufen begrenzen (5–7 sind gut lesbar)
  oder seltene Varianten vorher zu "Sonstige" zusammenfassen.

## In Databricks einrichten

1. `01_sample_event_log.sql` im SQL-Editor ausführen. Vorher Katalog und Schema anpassen,
   Standard ist `main.process_mining`.
2. **Variante A, Import:** *Dashboards → Create → Import dashboard from file* und
   `process_mining_sankey.lvdash.json` wählen.
3. **Variante B, manuell**, falls der Import beim Sankey-Widget meckert:
   * Neues Dashboard anlegen. Unter *Data* zwei Datasets aus `02_…` und `03_…` erstellen.
   * Visualisierung hinzufügen, Typ **Sankey**, Dataset `sankey_paths`.
     Stufen: `step_1` … `step_7`. Wert: `SUM(cases)`.
   * Zähler-Kacheln (Counter) auf `case_kpis` anlegen, z. B. `COUNT(case_id)` oder
     `AVG(is_cancelled) * 100`.
   * Einen Multi-Select-Filter auf `region` anlegen und mit beiden Datasets verbinden.

> **Hinweis:** Das genaue JSON-Schema des Sankey-Widgets (`widgetType: "sankey"`,
> Encodings `stages` + `value`) ist von Databricks nicht öffentlich dokumentiert. Im
> `.lvdash.json` ist es nach bestem Wissen nachgebildet. Falls nötig, das Widget im Editor
> einmal neu konfigurieren. Datasets, Filter und Kacheln sind davon nicht betroffen.

## Getestet

Die drei SQL-Dateien wurden lokal mit Apache Spark 4.0.1 ausgeführt. Ergebnis: 5.585 Events,
1.000 Fälle, 8 Varianten, Ø 4,8 Tage Durchlaufzeit, 13 % Storno, 24 % Nacharbeit. Diese Zahlen
zeigt auch das Mockup. Lokal ohne Delta musste nur `CREATE OR REPLACE TABLE` durch
`CREATE TABLE` ersetzt werden.
