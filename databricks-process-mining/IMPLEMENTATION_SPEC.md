# Implementierungsauftrag: Prozesskonformitäts-Dashboard in Databricks AI/BI

> Dieses Dokument ist die vollständige Übergabe an einen implementierenden Agenten.
> Es ist eigenständig lesbar. Ein funktionierender Referenzstand (SQL, Vega-Lite,
> HTML-Mockup) liegt im selben Ordner. Wo dieses Dokument und der Referenzcode sich
> widersprechen, gilt dieses Dokument.

---

## 1. Ziel

Für einen Geschäftsprozess (Beispiel: Order-to-Cash) gibt es einen definierten
**Standardprozess (Soll-Prozess)**. Ein Dashboard in **Databricks AI/BI** soll überwachen:

1. **Wird der Standardprozess eingehalten?** Anteil konformer Fälle und Verlauf über die Zeit.
2. **Wo wird abgewichen?** Welche Übergänge und Aktivitäten sind nicht vorgesehen?
3. **Lässt die Applikation dahinter andere Wege zu?** Für jeden unzulässigen Weg: Tritt er
   aktuell noch auf, oder ist er abgestellt?

Das Fachgebiet heißt *Conformance Checking* (Process Mining). Gefordert ist eine Lösung auf
Basis von **Directly-Follows-Beziehungen** (A → B direkt nacheinander im selben Fall).
Petri-Netze oder Token-Replay sind nicht gefordert.

### Rahmenbedingungen (vom Auftraggeber festgelegt)

* **Keine Databricks App:** zu teuer. Nur AI/BI Dashboards, SQL Warehouse und Delta-Tabellen.
* **Keine Heatmap oder Übergangsmatrix:** ausdrücklich nicht gewünscht.
* **Kein Sankey im Hauptdashboard:** ersetzt durch einen Prozessgraphen. Ein Sankey existiert
  nur als Alternative in `alternative_sankey/`.
* Der **Prozessgraph** soll aussehen wie ein klassischer Process-Mining-Graph: Start-Kreis,
  Aktivitäten als Kästen mit Anzahl, Pfeile mit Zahl, Liniendicke nach Häufigkeit,
  End-Kreis, Verlauf von oben nach unten.
* Sprache der Oberfläche: **Deutsch**. Zahlenformat deutsch (1.000; 49,0 %).

---

## 2. Referenzstand im Repository

Repository `stefanhaider/stefanhaider`, Branch `ccr-f1f6041b-rq5je9`, Ordner
`databricks-process-mining/`:

| Datei | Rolle |
|---|---|
| `01_sample_event_log.sql` | Synthetisches Eventlog (1.000 Fälle) mit zwei eingebauten Effekten, nur für Tests und Demo |
| `02_process_model.sql` | Soll-Prozess als zwei Tabellen |
| `03_process_graph_dataset.sql` | Dataset für den Prozessgraphen, inklusive Layout-Berechnung |
| `04_conformance_cases_dataset.sql` | Konformität je Fall |
| `05_deviations_dataset.sql` | Unzulässige Übergänge je Vorkommen, mit Typ |
| `06_deviation_summary_dataset.sql` | Unzulässige Übergänge je Übergang: Status „weiterhin möglich?“ |
| `process_graph.vl.json` | Vega-Lite-Spezifikation des Prozessgraphen (Custom Viz) |
| `process_mining.lvdash.json` | Entwurf der Dashboard-Exportdatei. **Ungetestet**, Format undokumentiert |
| `dashboard.html` | Interaktives Mockup: Soll-Zustand der Oberfläche |
| `dashboard_preview.png`, `process_graph_preview.png` | Screenshots des Soll-Zustands |
| `README.md` | Anwenderdoku |
| `IMPLEMENTATION_SPEC.md` | Dieses Dokument |

Alle SQL-Dateien wurden mit Apache Spark 4.0.1 lokal ausgeführt. Die Spezifikation rendert in
Vega-Lite 5.23 und 6.5 ohne Warnungen. **Nichts davon wurde in einem echten
Databricks-Workspace getestet.** Das ist die Hauptaufgabe.

---

## 3. Vor dem Start mit dem Auftraggeber klären

Diese Punkte sind offen. Nicht raten, nachfragen:

1. **Echtes Eventlog:** Tabellenname sowie Spaltennamen für Fall-ID, Aktivität und Zeitstempel.
   Gibt es eine Sortier-Hilfsspalte für Events mit identischem Zeitstempel? Welche
   Filterdimensionen gibt es (im Mockup: `region`)?
2. **Echter Soll-Prozess:** Liste der Aktivitäten in Reihenfolge, erlaubte Übergänge,
   zulässige Abbrüche (z. B. Storno nach Kreditprüfung) und erlaubte Alternativen
   (Verzweigungen).
3. **Laufende Fälle:** Wie erkennt man einen abgeschlossenen Fall? Ohne Regel zählen laufende
   Fälle als „Kein gültiger Abschluss“. Vorschläge: nur Fälle mit einer Ende-Aktivität werten,
   oder Fälle ohne Event seit X Tagen als abgeschlossen behandeln.
4. **Zielwert** für die Konformitätsrate. Im Mockup steht ein Beispielwert von 90 %.
5. **Zeitfenster für „tritt weiterhin auf“.** Im Mockup sind es 4 Wochen (28 Tage).
6. **Katalog und Schema.** Im Mockup: `main.process_mining`.
7. Ist **Custom Viz** im Workspace verfügbar (Public Preview), und welche Vega-Lite-Version
   läuft dort?

---

## 4. Datenmodell

### 4.1 Eventlog (Eingabe)

Eine Zeile pro Event. Mindestspalten (Namen ggf. per View auf die echte Tabelle abbilden):

| Spalte | Typ | Bedeutung |
|---|---|---|
| `case_id` | STRING | Fall-ID |
| `activity` | STRING | Name der Aktivität |
| `event_ts` | TIMESTAMP | Zeitpunkt |
| `step_no` | INT | Tie-Breaker bei gleichem Zeitstempel (sonst Konstante) |
| `region` | STRING | Beispiel für eine Filterdimension, optional |

**Empfehlung:** eine View `main.process_mining.event_log` auf die echte Quelle legen, damit alle
Datasets unverändert bleiben.

### 4.2 Soll-Prozess (`02_process_model.sql`)

```
process_model_activities(activity STRING, step_order INT, is_terminal BOOLEAN)
process_model_transitions(src STRING, tgt STRING)
```

* Die Pseudo-Aktivitäten `'▶ Start'` (step_order 0) und `'■ Ende'` (step_order 99,
  is_terminal true) gehören **immer** dazu.
* `process_model_transitions` enthält **alle** erlaubten direkten Übergänge, einschließlich
  `'▶ Start' → erste Aktivität` und `letzte Aktivität → '■ Ende'`.
* `is_terminal = true` markiert zulässige Ende-Aktivitäten (z. B. `Storniert`).
* `step_order` dient nur der Klassifizierung der Abweichungen (siehe 5.2). Parallele
  Alternativen bekommen denselben oder benachbarten Wert.
* Alles, was nicht in `process_model_transitions` steht, ist eine Abweichung.

### 4.3 Übergänge ableiten (gemeinsame Logik aller Datasets)

Je Fall nach `event_ts, step_no` sortieren und mit `LAG`/`LEAD` Paare bilden:

* `src = activity`, `tgt = COALESCE(LEAD(activity), '■ Ende')`
* zusätzlich je Fall: `'▶ Start' → erste Aktivität` (dort ist `LAG(activity) IS NULL`)
* Wartezeit eines Übergangs: `LEAD(event_ts) - event_ts` (in Stunden)
* Zeitpunkt eines Übergangs, z. B. für „zuletzt gesehen“: Zeitstempel des Ziel-Events

---

## 5. Datasets (je eine SQL-Datei = ein Dashboard-Dataset)

### 5.1 `conformance_cases` (04): eine Zeile je Fall

| Spalte | Logik |
|---|---|
| `case_id`, `region` | |
| `case_start` | `MIN(event_ts)` |
| `throughput_days` | `(MAX(event_ts) - MIN(event_ts))` in Tagen |
| `is_conformant` | 1, wenn **alle** Übergänge des Falls (inkl. Start/Ende) in `process_model_transitions` stehen, sonst 0 |
| `n_deviating_transitions` | Anzahl unzulässiger Übergänge |
| `deviations` | sortierte, eindeutige Liste der unzulässigen Übergänge `"A → B"`, getrennt durch `' \| '` |

### 5.2 `deviations` (05): eine Zeile je Vorkommen eines unzulässigen Übergangs

Spalten: `case_id, region, src, tgt, transition ("src → tgt"), event_ts, deviation_type`.

`deviation_type` wird in genau dieser Reihenfolge bestimmt (erster Treffer gewinnt).
`ms` und `mt` sind die Modellzeilen von `src` und `tgt`:

| # | Bedingung | Typ |
|---|---|---|
| 1 | `src` oder `tgt` nicht in `process_model_activities` | `Zusätzliche Aktivität` |
| 2 | `tgt = '■ Ende'` | `Kein gültiger Abschluss` |
| 3 | `mt.is_terminal` | `Abbruch an unzulässiger Stelle` |
| 4 | `mt.step_order <= ms.step_order` | `Rücksprung / Wiederholung` |
| 5 | `mt.step_order > ms.step_order + 1` | `Schritt übersprungen` |
| 6 | sonst | `Unzulässiger Übergang` |

### 5.3 `deviation_summary` (06): eine Zeile je unzulässigem Übergang

Optionaler Parameter `:region` (`'Alle'` = kein Filter). Spalten:

| Spalte | Logik |
|---|---|
| `deviation_type`, `transition` | wie 5.2 |
| `cases` | `COUNT(DISTINCT case_id)` |
| `pct_of_cases` | `cases / alle Fälle × 100` |
| `first_seen`, `last_seen` | `MIN`/`MAX` des Übergangszeitpunkts (DATE) |
| `cases_last_4w` | betroffene Fälle mit `case_start >= MAX(case_start aller Fälle) - 28 Tage` |
| `pct_last_4w` | `cases_last_4w` / alle Fälle mit Start in diesem Fenster × 100 |
| `status` | `'tritt weiterhin auf'`, wenn `cases_last_4w > 0`, sonst `'in den letzten 4 Wochen nicht mehr'` |

**Wichtige Details:**
* Bezugspunkt ist der **jüngste Fallstart**, nicht das letzte Event. Das letzte Event ist
  meist ein später Zahlungseingang und würde aktive Abweichungen fälschlich als „nicht mehr“
  ausweisen. Bei Live-Daten kann man alternativ `current_timestamp()` nehmen.
* Bei zusätzlichen Aktivitäten wird **nur der Übergang hinein** gelistet (Rechnung → Mahnung),
  nicht der Weg heraus (Mahnung → Zahlung). Sonst erscheint jede Abweichung doppelt. Filter:
  `NOT (src nicht im Modell AND tgt im Modell)`.
* Spark erlaubt keine verschachtelten Aggregate. Den Referenzwert in einer eigenen CTE
  berechnen (siehe Referenzcode).

### 5.4 `process_graph` (03): Daten und Layout für die Custom Viz

Optionaler Parameter `:region`. **Eine** Ergebnismenge mit mehreren Zeilentypen. Custom Viz
kann nur ein Dataset lesen.

| Spalte | Typ | Bedeutung |
|---|---|---|
| `row_type` | STRING | `node` \| `edge` \| `arrow` \| `label` |
| `id` | STRING | Aktivität bzw. `"src → tgt"` |
| `src`, `tgt` | STRING | bei edge, arrow und label |
| `cases` | BIGINT | Vorkommen der Aktivität bzw. Anzahl Übergänge |
| `median_wait_h` | DOUBLE | Median-Wartezeit des Übergangs |
| `x`, `y` | DOUBLE | Koordinaten im Raster 800 × 700 (y nach unten). Node: Mittelpunkt; edge: Stützpunkt; arrow: Pfeilposition; label: Pillen-Mittelpunkt |
| `w`, `h` | DOUBLE | nur bei node: Breite und Höhe (Aktivität 180 × 44, Start/Ende 28 × 28) |
| `seq` | INT | nur bei edge: Reihenfolge der Stützpunkte |
| `shape` | STRING | nur bei arrow: `triangle-down` \| `triangle-left` \| `triangle-right` |
| `node_kind` | STRING | `start` \| `end` \| `activity` |
| `conformance` | STRING | `soll` \| `abweichung`. Kanten: Übergang im Modell? Knoten: Aktivität im Modell? |

**Knotenzahlen:** Aktivität = Anzahl Events; Start/Ende = Anzahl Fälle.

**Layout:** In der CTE `layout` steht eine feste Position (x, y) je Aktivität. Das ist die einzige
Stelle, die für einen neuen Prozess angepasst wird. Empfehlung: Standardprozess senkrecht bei
x = 400 mit 80 Einheiten Abstand, Zusatz-Aktivitäten seitlich (x ≈ 150 oder 650). Aktivitäten
ohne Eintrag kommen automatisch an x = 740 untereinander.

**Kantenverlauf (rechtwinklig).** Typ je Kante in dieser Reihenfolge bestimmen:

| Typ | Bedingung | Verlauf |
|---|---|---|
| `self` | `src = tgt` | kleine Schleife oben rechts am Kasten, Pfeil nach links |
| `down_across` | Ziel ist `■ Ende` und x verschieden | am äußeren Rand der Quelle (x0 ± (w0/2 − 8)) senkrecht runter bis Höhe des End-Kreises, dann waagrecht in den Kreis |
| `skip` | senkrecht nach unten, aber ein anderer Kasten liegt dazwischen | links an der Quelle raus, auf eine Spur links von beiden Kästen (min(Rand) − 25 − 14·Rang), runter bis 12 Einheiten über dem Ziel, waagrecht zum Eingangspunkt, oben ins Ziel |
| `straight` | Ziel tiefer, \|x1 − x0\| < w0/2 | senkrecht vom unteren Rand der Quelle zum oberen Rand des Ziels |
| `side_down` | Ziel tiefer, seitlich versetzt | aus der Seitenkante der Quelle (zum Ziel hin), waagrecht bis zum Eingangspunkt, senkrecht oben ins Ziel |
| `same_row` | gleiche Höhe | waagrecht Seite zu Seite; nach rechts 11 Einheiten über, nach links 11 Einheiten unter der Mittellinie |
| `back` | Ziel höher | rechts raus, Spur rechts (max(Rand) + 25 + 14·Rang), hoch, rechts ins Ziel |

**Verteilung, damit sich Linien nicht kreuzen oder überlagern:**
* **Eingänge oben am Ziel** (straight, side_down, skip): Gruppen links (0), mittig (1), rechts
  (2). Links nach `y0` absteigend, sonst aufsteigend sortieren. Gleichmäßig verteilen über
  ±min(w1/2 − 20, 25·(n − 1)).
* **Seitliche Ausgänge** je Quelle und Seite: weiter entfernte Ziele steigen weiter oben aus.
  Verteilung ±min(h0/2 − 8, 8·(n − 1)).
* **Eingänge in den End-Kreis von der Seite:** ±5 Einheiten, weiter entfernte Quellen weiter unten.

**Pfeilspitze:** 5 Einheiten vor dem Endpunkt, entgegen der Laufrichtung. **Beschriftung:**
Mitte des senkrechten Hauptsegments; bei same_row Mitte der Waagrechten.

---

## 6. Prozessgraph: Vega-Lite-Spezifikation (`process_graph.vl.json`)

* `"data": {"name": "databricks_query"}`, `"width"`/`"height": "container"`.
* Gemeinsame Skalen in **jedem** Layer explizit:
  * x: Domain [0, 800]
  * y: Domain [0, 700], `reverse: true`
  * jeweils `nice: false`, `zero: false`, `axis: null`
* Layer in dieser Reihenfolge, jeweils mit Filter auf `row_type`:

| Layer | Mark | Kodierung |
|---|---|---|
| Kanten | `line` | `detail = id`, `order = seq`; `strokeWidth = cases` (sqrt, 1–7 px); `color` und `strokeDash` je nach `conformance`: soll = `#8f8e88` durchgezogen, abweichung = `#eb6834` gestrichelt `[6,4]`. Gemeinsame Legende oben links, vertikal, Labels „Laut Soll-Prozess“ / „Abweichung“ |
| Pfeile | `point`, gefüllt | `shape = shape` (scale null); `size = cases` (sqrt, 45–190); Farbe wie Kanten |
| Beschriftungen | `point` + `text` | Pille als eigener SVG-Pfad je Zeile (Breite abhängig von der Ziffernanzahl, `size` 196), weiß gefüllt, Rand grau bzw. orange; Zahl deutsch formatiert (`replace(format(cases, ','), ',', '.')`), 10 px. Tooltip: Von, Nach, Status, Übergänge, Median-Wartezeit |
| Kästen soll | `rect`, Radius 3 | aus x ± w/2, y ± h/2; Füllung nach `cases` von `#f4f8fd` bis `#86b6ef`, Rand `#6da7ec` |
| Kästen Abweichung | `rect`, Radius 3 | Füllung `#fdf0ea`, Rand `#eb6834`, `strokeDash [4,3]` als **Mark-Eigenschaft** (bei rect nicht als Kodierung möglich) |
| Kastentext | `text` | Name fett 11 px (dy −7), Anzahl 10 px (dy +8), linksbündig bei x − w/2 + 8 |
| Start/Ende | `point` | Kreis (size 420, weiß, Rand grau) plus Symbol `triangle-right` bzw. `square` |

* Farben sind fest gesetzt und funktionieren in hellem und dunklem Theme. Keine Theme-Farben
  voraussetzen.
* Muss in Vega-Lite 5 **und** 6 ohne Warnungen kompilieren.

---

## 7. Dashboard-Aufbau (eine Seite „Konformität“)

Raster mit 6 Spalten. Zielbild: `dashboard_preview.png`.

1. **Filterzeile:** Zeitraum (auf `case_start`), Region (Multi-Select, auf alle Datasets bzw. den
   Parameter `:region`), Soll-Prozess-Version (zunächst statisch).
2. **Sechs Zähler:**
   * Fälle
   * Konformitätsrate in % (`AVG(is_conformant) × 100`) mit Unterzeile „letzte 4 Wochen: x %“
   * Fälle mit Abweichung
   * Unzulässige Wege (`COUNT(*)` auf `deviation_summary`) mit Unterzeile „davon n weiterhin möglich“
   * Häufigste Abweichung (Top-Zeile von `deviation_summary`)
   * Ø Durchlaufzeit mit Abweichung, Vergleich mit konformen Fällen
3. **Links, doppelte Höhe:** Soll-Ist-Prozessgraph (Custom Viz, Breite : Höhe ≈ 8 : 7).
   **Rechts oben:** Linie „Konformitätsrate je Startwoche“ (Y 0–100 %), Ziellinie und
   Markierung von Ereignissen. **Rechts unten:** Balken „Fälle je Abweichungstyp“ (horizontal,
   absteigend).
4. **Tabelle „Unzulässige Übergänge – lässt die Applikation das noch zu?“:** Status mit Icon und
   Text, Abweichungstyp, Übergang, Fälle, Anteil gesamt, Anteil letzte 4 Wochen, Erstmals,
   Zuletzt. Sortiert nach Fällen.
5. **Tabelle „Abweichende Fälle“:** Fall, Region, Start, Durchlaufzeit, unzulässige Übergänge.
   Gefiltert auf `is_conformant = 0`.

Statusfarben (orange/grün) immer mit Icon und Text, nie nur über Farbe.

---

## 8. Umsetzungsschritte

1. Punkte aus Abschnitt 3 klären.
2. View `event_log` auf die echte Quelle anlegen. Soll-Prozess in `02_process_model.sql`
   eintragen und ausführen.
3. Datasets 03–06 im Workspace anlegen und einzeln im SQL-Editor ausführen. Dann Parameter
   `:region` mit Standardwert `Alle` anlegen.
4. Regel für laufende Fälle einbauen (Ergebnis aus Klärungspunkt 3), konsistent in 03–06.
5. `layout`-CTE in 03 für den echten Prozess setzen. Graph prüfen: keine Linie durch einen
   Kasten, keine überlappenden Beschriftungen.
6. Dashboard anlegen: native Widgets laut Abschnitt 7, dann die Custom Viz mit
   `process_graph.vl.json`. Die Felder **ohne Aggregation** hinzufügen:
   `row_type, id, src, tgt, cases, median_wait_h, x, y, w, h, seq, shape, node_kind, conformance`.
7. Optional: Wenn der Import von `process_mining.lvdash.json` funktioniert, diesen nutzen.
   Sonst manuell aufbauen und den fertigen Stand als `.lvdash.json` **exportieren** und
   versionieren. Der Export ist die verlässliche Formatquelle.
8. Optional: Benachrichtigung einrichten, wenn ein neuer unzulässiger Übergang auftaucht
   (`first_seen` innerhalb der letzten 7 Tage), z. B. über Databricks SQL Alerts auf
   `deviation_summary`.

---

## 9. Abnahmekriterien

### Mit den Beispieldaten (`01_sample_event_log.sql` + `02_process_model.sql`)

Diese Werte müssen exakt herauskommen:

| Prüfung | Erwartet |
|---|---|
| Fälle | 1.000 |
| Konforme Fälle / Rate | 490 / 49,0 % |
| Ø Durchlaufzeit konform / abweichend | 12,3 / 15,6 Tage |
| Fälle je Typ | Schritt übersprungen 320 · Zusätzliche Aktivität 240 · Abbruch an unzulässiger Stelle 60 |
| `deviation_summary` | 6 Zeilen. `Auftrag angelegt → Auftrag freigegeben`: 320 Fälle, erstmals 02.03.2026, 41,7 % der letzten 4 Wochen, „tritt weiterhin auf“. `Auftrag angelegt → Storniert`: 25 Fälle, zuletzt 04.04.2026, „in den letzten 4 Wochen nicht mehr“. Die übrigen 4 Zeilen: „tritt weiterhin auf“ |
| Konformitätsrate je Woche | KW 2–9 zwischen 54,8 und 81,8 %, ab KW 10 zwischen 30,4 und 58,7 % |
| `process_graph` | 12 Knoten (10 Aktivitäten + Start + Ende). Abweichend: Preisänderung, Mahnung, Gutschrift sowie die Kanten Angelegt → Freigegeben (320), Angelegt → Storniert (25), Lieferung → Storniert (35), Freigegeben ⇄ Preisänderung (je 60), Rechnung → Mahnung (130), Mahnung → Zahlung (130), Rechnung → Gutschrift (50), Gutschrift → Ende (50) |
| Regionsfilter | `:region = 'DACH'` liefert ein kleineres, gültiges Ergebnis ohne Fehler |

### Allgemein

* Jedes Dataset läuft im SQL Warehouse ohne Fehler.
* Die Custom Viz rendert ohne Konsolenfehler. Tooltips auf Kästen und Zahlen funktionieren.
* Hell- und Dunkel-Theme sind lesbar.
* Eine Änderung nur an `02_process_model.sql` wirkt in allen Widgets, ohne weitere Anpassung.
* Kein Element nutzt eine Databricks App.

---

## 10. Bekannte Risiken und Fallstricke

* **`.lvdash.json`-Format ist undokumentiert.** Die Widget-Definitionen im Entwurf sind
  geraten. Nach manuellem Aufbau den echten Export als Referenz nehmen.
* **Custom Viz ist Public Preview.** Verhalten und Vega-Lite-Version können sich ändern.
* **Feldnamen in Custom Viz:** Sie müssen exakt den Spaltennamen entsprechen und dürfen nicht
  aggregiert sein. Sonst sind die Daten leer oder zusammengefasst.
* **Widget-Größe:** Die Skalen haben eine feste Domain. Ein stark abweichendes
  Seitenverhältnis verzerrt die Kästen, die Schrift bleibt gleich groß.
* **Laufende Fälle** verfälschen „Kein gültiger Abschluss“ und die Konformitätsrate
  (siehe Abschnitt 3).
* **Spark SQL:** keine verschachtelten Aggregate. `sequence(1, 0)` liefert `[1, 0]` statt eines
  leeren Arrays. `CREATE OR REPLACE TABLE` braucht Delta (im Workspace gegeben).
* **Große Eventlogs:** Die Datasets aggregieren erst am Ende. Bei vielen Millionen Events
  `seq`/`trans` als materialisierte Tabelle bzw. per Job vorberechnen.
* **Layout-Pflege:** Neue Aktivitäten landen automatisch rechts. Für eine saubere Darstellung
  einen Eintrag in `layout` ergänzen.

---

## 11. Lokal testen ohne Workspace (optional)

* **SQL:** PySpark 4.x lokal; `main.process_mining.` durch ein lokales Schema ersetzen,
  `CREATE OR REPLACE TABLE` durch `CREATE TABLE`, Parameter über
  `spark.sql(query, args={"region": "Alle"})`.
* **Vega-Lite:** `npm i vega vega-lite` (je einmal v5 und v6). Spezifikation laden,
  `data` durch `{"values": [...]}` ersetzen, mit `vl.compile` und `new vega.View(...).toSVG()`
  rendern. Kompilier-Warnungen müssen leer sein.
* **Gesamtbild:** `dashboard.html` im Browser öffnen. Die Datei enthält Daten und Bibliotheken
  und funktioniert offline.
