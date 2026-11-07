# Implementierungsauftrag: Prozess- und Governance-Monitoring für den „Data Manager“

> Vollständige Übergabe an einen implementierenden Agenten oder ein Team. Das Dokument ist
> eigenständig lesbar. Ein funktionierender Referenzstand (SQL, Vega-Lite, HTML-Mockup) liegt im
> selben Ordner. Wo Dokument und Referenzcode sich widersprechen, gilt dieses Dokument.

---

## 1. Kontext und Ziel

Das Unternehmen betreibt eine eigene Data-Governance- bzw. Data-Mesh-Applikation, den
**Data Manager**. Er verwaltet unter anderem:

- den **Datenkatalog**,
- **Data Contracts** und **Data Products**,
- **Applikationen**,
- **Access Requests** und **Change Approvals**,
- **kanonische Datenmodelle**.

Die Prozesse dahinter sind definiert und in der Applikation implementiert.

**Ziel:** Mit Process Mining messen, ob die **Ist-Prozesse den definierten Soll-Prozessen
entsprechen**, und **informiert werden**, sobald Prozesslücken oder Governance-Brüche sichtbar
werden, um gezielt handeln zu können. Im Kern sind es drei Fragen:

1. **Werden die Soll-Prozesse eingehalten?** Konformitätsrate je Prozess und Verlauf.
2. **Lässt der Data Manager Wege zu, die er nicht zulassen sollte?** Zum Beispiel eine
   Berechtigung ohne Security-Prüfung, ein Datenprodukt ohne Qualitätsprüfung, eine
   Contract-Änderung ohne Review. Tritt das **noch** auf, ist es **neu**, oder ist es behoben?
3. **Werden Governance-Regeln verletzt, die sich nicht am Pfad zeigen?** Funktionstrennung
   (Antragsteller ≠ Genehmiger) und Fristen.

Fachlich ist das **Conformance Checking** auf Basis von Directly-Follows-Beziehungen
(A → B direkt nacheinander im selben Vorgang), ergänzt um Regelprüfungen.
**Kein** generisches Process-Mining-Tool, **keine** Petri-Netze oder Token-Replay.

### Rahmenbedingungen (vom Auftraggeber festgelegt)

* **Plattform:** Databricks. Delta-Tabellen, Views, SQL Warehouse, **AI/BI Dashboards** und
  SQL Alerts.
* **Keine Databricks App:** zu teuer.
* **Keine Heatmap oder Übergangsmatrix, kein Sankey** im Dashboard. Stattdessen ein
  **Prozessgraph** im klassischen Process-Mining-Stil: Start/Ende-Kreise, Kästen mit Anzahl,
  Pfeile mit Zahl, Liniendicke nach Häufigkeit, Verlauf von oben nach unten.
* Sprache **Deutsch**, Zahlenformat deutsch (1.000; 74,5 %).
* **Erweiterbar** auf weitere Data-Manager-Prozesse (Change Approval, kanonische Datenmodelle,
  Applikations-Onboarding, …) **nur über Konfiguration**, ohne Codeänderung.

---

## 2. Referenzstand im Repository

Repository `stefanhaider/stefanhaider`, Branch `ccr-f1f6041b-rq5je9`, Ordner
`databricks-process-mining/`:

| Datei | Rolle |
|---|---|
| `01_sample_event_log.sql` | Synthetisches Eventlog: 1.000 Vorgänge in 3 Prozessen, mit eingebauten Governance-Lücken. Nur für Demo und Abnahme |
| `02_process_model.sql` | **Konfiguration:** Prozesse, Soll-Prozesse, Kontrollschritte, Regeln, Schweregrade, Graph-Layout |
| `03_views.sql` | **Gesamte Auswertungslogik** als 4 Views |
| `04_ds_process_graph.sql` | Dataset Prozessgraph (inkl. Layout-Berechnung), Parameter `:process`, `:domain` |
| `05_ds_case_conformance.sql` | Dataset: ein Datensatz je Vorgang |
| `06_ds_findings.sql` | Dataset: jedes Befund-Vorkommen |
| `07_ds_findings_summary.sql` | Dataset: je Befund Status „neu / tritt weiterhin auf / nicht mehr aufgetreten“, Parameter `:domain` |
| `08_alert_critical_findings.sql` | Abfrage für einen SQL Alert auf neue bzw. aktuelle kritische Befunde |
| `process_graph.vl.json` | Vega-Lite-Spezifikation des Prozessgraphen (Custom Viz) |
| `process_mining.lvdash.json` | Entwurf der Dashboard-Exportdatei (2 Seiten). **Ungetestet**, Format undokumentiert |
| `dashboard.html` | Interaktives Mockup = **Soll-Zustand der Oberfläche** (Seiten „Übersicht“ und „Prozessdetail“) |
| `dashboard_preview.png`, `dashboard_detail_preview.png`, `process_graph_preview.png` | Screenshots des Soll-Zustands |

Alle SQL-Dateien wurden mit Apache Spark 4.0.1 lokal ausgeführt, die parametrisierten mit
mehreren Werten. Die Spezifikation rendert in Vega-Lite 5.23 und 6.5 ohne Warnungen.
**Nichts davon wurde in einem echten Databricks-Workspace getestet.** Das ist die Hauptaufgabe.

---

## 3. Vor dem Start mit dem Auftraggeber klären

1. **Quelle der Events im Data Manager:** Wo liegt das Audit-, Workflow- oder Statushistorie-Log?
   Tabelle oder Export, Aktualität (Streaming oder Batch). Welche Felder gibt es (siehe 4.1)?
2. **Welche Prozesse zuerst?** Vorschlag: Access Request, Data Contract, Data Product.
   Danach Change Approval und kanonische Datenmodelle.
3. **Soll-Prozesse je Prozess:**
   - Statusfolge,
   - erlaubte Alternativen und Rücksprünge,
   - zulässige Endzustände (z. B. Abgelehnt, Verworfen),
   - **welche Schritte sind Kontrollen** (Genehmigung, Prüfung, Validierung)?
4. **Governance-Regeln:** Funktionstrennung (welche Schritte nicht durch dieselbe Person?),
   Fristen (von–bis, maximale Dauer). Gibt es Ausnahmen, z. B. technische Accounts oder
   Notfallzugriffe?
5. **Laufende Vorgänge:** Woran erkennt man „abgeschlossen“? Sonst erscheinen laufende Vorgänge
   als „Kein gültiger Abschluss“, und Fristverletzungen offener Vorgänge fehlen.
6. **Verantwortliche** je Prozess (Process Owner) und **Alarm-Empfänger** (E-Mail, Teams/Slack,
   Ticket?).
7. **Zielwerte:** Konformitätsziel je Prozess (im Mockup Beispiel 95 %), Zeitfenster für
   „aktuell“ (4 Wochen) und „neu“ (8 Wochen).
8. **Katalog und Schema** (Mockup: `main.data_manager_pm`), Berechtigungen. Das Eventlog enthält
   Personenkennungen, daher Datenschutz und Zugriff auf das Dashboard klären.
9. Ist **Custom Viz (Public Preview)** im Workspace verfügbar, und welche Vega-Lite-Version
   läuft dort?

---

## 4. Datenmodell

### 4.1 Eventlog (Eingabe): `main.data_manager_pm.event_log`

Eine Zeile pro Statuswechsel oder Aktion im Data Manager. **Empfehlung:** eine View auf das echte
Audit- bzw. Workflow-Log, die diese Spalten liefert:

| Spalte | Typ | Bedeutung | Typische Herkunft im Data Manager |
|---|---|---|---|
| `process` | STRING | Prozessname, muss `process_catalog.process` entsprechen | Objekttyp bzw. Workflow-Typ (Access Request, Data Contract, …) |
| `case_id` | STRING | Vorgangs-ID | ID des Antrags, Contracts oder Produkts (bei Versionierung: ID + Version oder Änderungs-ID) |
| `domain` | STRING | Filterdimension, z. B. Datendomäne | Domäne bzw. Owner-Team des Objekts |
| `activity` | STRING | Name des Schritts bzw. Status | Neuer Status oder Aktion, auf Soll-Namen gemappt |
| `actor` | STRING | ausführende Person bzw. technischer Account | User des Audit-Eintrags |
| `event_ts` | TIMESTAMP | Zeitpunkt | Zeitstempel des Audit-Eintrags |
| `step_no` | INT | Tie-Breaker bei gleichem Zeitstempel | Sequenz oder ID des Audit-Eintrags |

Wichtig: Gleiche fachliche Schritte müssen **denselben `activity`-Namen** haben wie im Soll-Modell.
Das Mapping von technischen Statuscodes auf Namen gehört in die View.

### 4.2 Konfiguration (`02_process_model.sql`): einzige Pflegestelle

| Tabelle | Spalten | Zweck |
|---|---|---|
| `process_catalog` | process, owner, description | Prozesse und Verantwortliche |
| `process_model_activities` | process, activity, step_order, is_terminal, is_control | Aktivitäten je Prozess. `step_order` = Soll-Reihenfolge. `is_terminal` = zulässiges Ende (z. B. Abgelehnt). **`is_control` = Kontrollschritt**: Umgehung gilt als kritisch. `'▶ Start'` (0) und `'■ Ende'` (99, terminal) müssen je Prozess vorhanden sein |
| `process_model_transitions` | process, src, tgt | **Alle erlaubten** direkten Übergänge inkl. Start/Ende, erlaubter Rücksprünge (z. B. Qualitätsprüfung → Metadaten erfasst) und Alternativen. Alles andere ist ein Befund |
| `governance_rules` | process, rule_id, rule_type, activity_a, activity_b, max_hours, description, severity | `sod`: a und b nicht durch dieselbe Person. `sla`: von a bis b höchstens `max_hours` |
| `finding_severity` | finding_type, severity, severity_rank, recommended_action | Schweregrad (kritisch/hoch/mittel) und empfohlene Maßnahme je Befund-Typ |
| `process_graph_layout` | process, activity, x, y | Position im Prozessgraphen (Raster 800 breit, y nach unten). Fehlende Aktivitäten kommen automatisch an x = 740 untereinander |

**Referenz-Konfiguration** (Beispiel, mit dem Auftraggeber zu ersetzen; ◆ = Kontrollschritt):

* **Access Request:** Beantragt → ◆ Prüfung Data Owner → ◆ Prüfung Security → Berechtigung
  erteilt. Abgelehnt ist nach beiden Prüfungen zulässig.
  - Funktionstrennung: Beantragt ≠ Prüfung Data Owner.
  - Frist: Beantragt → Berechtigung erteilt ≤ 5 Tage.
* **Data Contract:** Entwurf erstellt → ◆ Schema validiert → ◆ Review Data Owner → Freigegeben →
  Aktiv. Verworfen ist nach dem Review zulässig.
  - Änderungszyklus: Aktiv → Änderung beantragt → ◆ Schema erneut validiert → ◆ Review Änderung →
    Neue Version aktiv.
  - Funktionstrennung: Entwurf ≠ Review.
  - Frist: Entwurf → Freigegeben ≤ 7 Tage.
* **Data Product:** Angelegt → Metadaten erfasst → ◆ Data Contract verknüpft → ◆ Qualitätsprüfung
  → ◆ Freigabe Data Owner → Veröffentlicht.
  - Nachbesserung erlaubt: Qualitätsprüfung → Metadaten erfasst.
  - Abgelehnt ist nach der Freigabe-Prüfung zulässig.
  - Funktionstrennung: Angelegt ≠ Freigabe.
  - Frist: Angelegt → Veröffentlicht ≤ 10 Tage.

---

## 5. Auswertungslogik (`03_views.sql`)

### 5.1 `v_transitions`: jeder direkte Übergang je Vorgang

* Je `process, case_id` nach `event_ts, step_no` sortieren.
* Übergang: `src = activity`, `tgt = COALESCE(LEAD(activity), '■ Ende')`.
* Zusätzlich je Vorgang ein Übergang `'▶ Start' → erste Aktivität`.
* Spalten:
  - `src_ts`, `tgt_ts`
  - `actor` (Person des Ziel-Events)
  - `wait_h` (für Start und Ende NULL)
  - `is_allowed`, `src_in_model`, `tgt_in_model`
  - `skipped_controls`: Kontrollschritte mit `step_order` zwischen src und tgt, in Soll-Reihenfolge
  - `finding_type`
* **`finding_type`**: erster Treffer gewinnt. `ms`/`mt` sind die Modellzeilen von src/tgt.

| # | Bedingung | Typ | Standard-Schwere |
|---|---|---|---|
| 0 | Übergang in `process_model_transitions` | NULL (erlaubt) | – |
| 1 | src oder tgt nicht im Modell | Zusätzliche Aktivität | mittel |
| 2 | tgt = `■ Ende` | Kein gültiger Abschluss | hoch |
| 3 | `mt.is_terminal` | Abbruch an unzulässiger Stelle | hoch |
| 4 | `mt.step_order <= ms.step_order` | Rücksprung / Wiederholung | mittel |
| 5 | `skipped_controls` nicht leer | **Kontrolle umgangen** | **kritisch** |
| 6 | `mt.step_order > ms.step_order + 1` | Schritt übersprungen | hoch |
| 7 | sonst | Unzulässiger Übergang | hoch |

### 5.2 `v_rule_violations`: Funktionstrennung und Fristen

* Je Vorgang und Aktivität das **erste** Vorkommen ermitteln (Zeit und Person, `MIN_BY`).
* `sod`: Verstoß, wenn Person(a) = Person(b) → `Funktionstrennung verletzt`, Text = `description`.
* `sla`: Verstoß, wenn Dauer(a → b) > `max_hours` → `Frist überschritten`, Text =
  `"a → b über N Tage"`.
* Schweregrad aus `governance_rules.severity`.
* *Erweiterung (offen):* Fristverletzung auch für **offene** Vorgänge (b fehlt, a älter als Frist).

### 5.3 `v_findings`: alle Befunde je Vorgang

UNION aus Pfad-Befunden (`v_transitions` mit `finding_type`) und Regelverstößen.

Spalten: `process, case_id, domain, finding_type, finding, transition, event_ts, actor, severity,
severity_rank, recommended_action, source`.

`finding` (lesbarer Text):

| Typ | Text |
|---|---|
| Kontrolle umgangen | `"<skipped_controls> umgangen"` |
| Zusätzliche Aktivität | `"Zusätzlicher Schritt: <Aktivität>"` |
| Rücksprung | `"Rücksprung: src → tgt"` |
| sonst | `"src → tgt"` |

Der **Rückweg aus einer Zusatz-Aktivität** (src nicht im Modell, tgt im Modell) wird **nicht**
gezählt. Sonst erscheint jede Zusatz-Aktivität doppelt.

### 5.4 `v_case_conformance`: ein Datensatz je Vorgang

`process, case_id, domain, initiator` (Person des ersten Events), `case_start`, `throughput_days`,
außerdem:

| Spalte | Bedeutung |
|---|---|
| `is_conformant` | alle Übergänge erlaubt |
| `is_compliant` | konform **und** kein Regelverstoß |
| `n_findings` | Anzahl Befunde |
| `has_critical`, `has_control_bypass`, `has_sod_violation`, `has_sla_breach` | Flags je Befund-Art |
| `findings` | sortierte, eindeutige Liste mit `' \| '` |

---

## 6. Dashboard-Datasets

| Dataset | Datei | Inhalt |
|---|---|---|
| `process_graph` | 04 | Graph-Zeilen eines Prozesses (siehe 7). Parameter `:process` (Pflicht), `:domain` (`'Alle'` = alle) |
| `case_conformance` | 05 | `v_case_conformance` + `process_owner` |
| `findings` | 06 | `v_findings` + `process_owner` |
| `findings_summary` | 07 | je `process, finding_type, finding, severity` (siehe unten), Parameter `:domain` |

`findings_summary` enthält: `cases`, `pct_of_cases`, `cases_last_4w`, `pct_last_4w`, `first_seen`,
`last_seen`, `status`, `recommended_action`, `process_owner`.

* „Letzte 4 Wochen“ = Vorgänge mit `case_start >= MAX(case_start des Prozesses) - 28 Tage`.
  Bezug ist der **jüngste Vorgangsstart**, nicht das letzte Event. Späte Events würden aktive
  Befunde sonst als erledigt zeigen. Bei Live-Daten ist `current_timestamp()` möglich.
* `status`:
  - `'neu'`, wenn das erste Vorkommen in den letzten **8 Wochen** liegt,
  - sonst `'tritt weiterhin auf'`, wenn ein Vorkommen in den letzten 4 Wochen liegt,
  - sonst `'nicht mehr aufgetreten'`.
* Sortierung: `severity_rank`, dann `cases_last_4w` absteigend.

**Alarm (`08_alert_critical_findings.sql`):** kritische Befunde mit Vorkommen in den letzten
7 Tagen oder neu (8 Wochen). Enthält `example_cases` (5 IDs) und `process_owner`. Als
**Databricks SQL Alert** täglich, Bedingung „Zeilen > 0“, Empfänger je Process Owner.

Spark/Databricks-Fallstricke:
* keine verschachtelten Aggregate (Referenzwerte in eigener CTE),
* `sequence(1, 0)` liefert `[1, 0]`,
* `MIN_BY` für „Person des ersten Events“.

---

## 7. Prozessgraph

### 7.1 Dataset `process_graph` (04): Layout in SQL

Vega-Lite kann Graphen nicht anordnen, darum liefert SQL alle Geometrien in **einer**
Ergebnismenge:

| Spalte | Bedeutung |
|---|---|
| `row_type` | `node` \| `edge` (Stützpunkte, Reihenfolge `seq`) \| `arrow` \| `label` \| `frame` (2 unsichtbare Eckpunkte (0,0) und (800, Höhe), legen den Zeichenbereich fest) |
| `id`, `src`, `tgt`, `cases`, `median_wait_h` | Knoten: Anzahl Ziel-Events; Start/Ende: Anzahl Vorgänge. Kante: Anzahl Übergänge |
| `x`, `y`, `w`, `h` | Koordinaten; Knoten = Mittelpunkt, Aktivität 180 × 44, Start/Ende 28 × 28 |
| `shape` | Pfeilrichtung `triangle-down/left/right` |
| `node_kind` | `start` \| `end` \| `activity` |
| `is_control` | 1 = Kontrollschritt |
| `conformance` | `soll` \| `abweichung` \| `kontrolle_umgangen`; Knoten: im Modell? |
| `finding_type` | für Tooltips |

**Kantenverlauf (rechtwinklig).** Typ in dieser Reihenfolge bestimmen:

| Typ | Bedingung | Verlauf |
|---|---|---|
| `self` | src = tgt | Schleife oben rechts |
| `down_across` | Ziel = Ende, x verschieden | am äußeren Rand der Quelle (x0 ± (w0/2 − 8)) senkrecht bis zur Höhe des End-Kreises, dann waagrecht hinein |
| `skip` | senkrecht nach unten, aber ein Kasten liegt dazwischen | links raus; Spur links: `min(linker Rand) − 25 − 14·r` (r = globaler Rang nach Sprunglänge, kurze innen); runter bis `y1 − h1/2 − 10 − 8·rt` (rt = Rang je Ziel, längster Sprung zuerst); waagrecht zum Eingang; oben hinein |
| `straight` | Ziel tiefer, \|Δx\| < w0/2 | senkrecht |
| `side_down` | Ziel tiefer, seitlich | aus der Seitenkante (zum Ziel hin), waagrecht, dann senkrecht oben hinein |
| `same_row` | gleiche Höhe | waagrecht; nach rechts 11 über, nach links 11 unter der Mitte |
| `back` | Ziel höher | rechts raus (y0 − 8), Spur rechts `max(rechter Rand) + 25 + 14·r`, hoch, rechts hinein (y1 + 8) |

**Verteilung, damit sich nichts kreuzt:**
* **Eingänge oben am Ziel:** Gruppen skip (−1, Sprunglänge absteigend), von links (0, `y0`
  absteigend), senkrecht (1), von rechts (2, `y0` aufsteigend). Verteilt über
  ±min(w1/2 − 20, 25·(n − 1)).
* **Seitliche Ausgänge** je Quelle und Seite: entferntere Ziele weiter oben;
  ±min(h0/2 − 8, 8·(n − 1)).
* **Seitliche Eingänge in den End-Kreis:** ±5.

**Pfeilspitze:** 5 Einheiten vor dem Endpunkt. **Beschriftung:** Mitte des senkrechten
Hauptsegments.

**Layout-Empfehlung:** Standardprozess senkrecht bei x = 400 mit 80 Einheiten Abstand,
Endzustände und Nebenzyklen seitlich (x ≈ 150 / 660).

### 7.2 Vega-Lite (`process_graph.vl.json`)

* `"data": {"name": "databricks_query"}`, `width/height: "container"`.
* Skalen x/y **ohne feste Domain** (`nice: false, zero: false`, y `reverse: true`). Die
  `frame`-Zeilen bestimmen die Ausdehnung. Die Höhe passt sich je Prozess an.
* Ebenen:
  - **Kanten** (`line`, `detail = id`, `order = seq`, `strokeWidth` = sqrt 1–7 px). Farbe und
    Strich nach `conformance`: soll `#8f8e88` durchgezogen, abweichung `#eb6834` gestrichelt,
    kontrolle_umgangen `#d03b3b` gestrichelt. Legende oben links, vertikal.
  - **Pfeile** (`point`, `shape` ohne Skala, `size` = sqrt 45–190).
  - **Beschriftungs-Pillen** (eigener SVG-Pfad je Zeile, Breite nach Ziffern) mit Tooltip:
    Von, Nach, Befund, Übergänge, Median-Wartezeit.
  - **Kästen soll** (Füllung nach `cases` `#f4f8fd`–`#86b6ef`, Rand `#6da7ec`).
  - **Kästen abweichung** (`#fdf0ea`, Rand orange, `strokeDash` **als Mark-Eigenschaft**). Diese
    Ebene bekommt zusätzlich die `frame`-Zeilen mit Deckkraft 0, damit sie nie leer ist (sonst
    Warnung „Infinite extent“).
  - **Text** (Name fett 11 px, Anzahl 10 px).
  - **Kontroll-Markierung** „◆ KONTROLLE“ rechts in der Zeile mit der Anzahl.
  - **Start/Ende-Kreise.**
* Feste Farben, funktionieren in hellem und dunklem Theme. Muss in Vega-Lite 5 **und** 6 ohne
  Warnungen kompilieren.

---

## 8. Dashboard (2 Seiten)

Zielbild: `dashboard_preview.png` (Übersicht) und `dashboard_detail_preview.png` (Detail).

### Seite „Übersicht“ (Governance-Lage über alle Prozesse)

1. **Filter:** Zeitraum (`case_start`), Datendomäne.
2. **Hinweisbanner**, wenn ein **neuer kritischer Befund** existiert: Prozess, Befund, Anzahl,
   seit wann, Verantwortlicher. Quelle: `findings_summary` mit `status = 'neu'`.
3. **Sechs Zähler:**
   - Vorgänge
   - Prozesskonformität (`AVG(is_conformant)`)
   - Governance-konform (`AVG(is_compliant)`)
   - Vorgänge mit kritischem Befund
   - Aktive kritische Befunde (kritisch und Status ≠ nicht mehr)
   - Neue Befunde
4. **Je Prozess eine Karte:** Process Owner, Konformitätsrate, Mini-Verlauf, Zahlen (Vorgänge,
   Kontrolle umgangen, Funktionstrennung, Frist) und der wichtigste aktive kritische Befund.
   Klick öffnet die Detailseite mit diesem Prozess.
5. **Linie „Prozesskonformität je Startmonat“** (eine Linie je Prozess, nur volle Monate,
   Ziellinie, Ereignismarkierung) und **Balken „Betroffene Vorgänge je Prozess und Befund-Typ“**.
6. **Tabelle „Handlungsbedarf“:** aktive Befunde mit Schwere (Icon und Text), Status (neu /
   weiterhin), Prozess, Befund, letzte 4 Wochen (Anzahl und %), gesamt, erstmals, verantwortlich,
   empfohlene Maßnahme.
7. **Tabelle „Nicht mehr aufgetreten“:** Wirksamkeit umgesetzter Maßnahmen.

### Seite „Prozessdetail“

1. **Prozess-Auswahl** (Single Select, bindet den Parameter `:process` des Graphen und filtert
   die anderen Datasets), Datendomäne, Anzeige des Process Owners.
2. **Zähler:** Vorgänge, Konformität (mit Governance-konform), Kontrolle umgangen,
   Funktionstrennung verletzt, Frist überschritten, Ø Durchlaufzeit (konform vs. abweichend).
3. **Links, doppelte Höhe:** Soll-Ist-Prozessgraph (Custom Viz). **Rechts:** Konformität je
   Startwoche (mit Ereignis) und Befund-Typen.
4. **Tabelle Befunde des Prozesses:** inkl. „nicht mehr aufgetreten“.
5. **Tabelle betroffene Vorgänge:** Vorgang, Domäne, gestartet von, Start, Durchlaufzeit,
   Befunde. Das ist der Drill-down für die Klärung im Data Manager.

Schwere und Status nie nur über Farbe zeigen, immer mit Icon und Text. Statusfarben (rot,
orange, grün) nur dafür verwenden.

---

## 9. Umsetzungsschritte

1. Punkte aus Abschnitt 3 klären.
2. View `event_log` auf das Data-Manager-Log anlegen, inklusive Status-Mapping. Plausibilität
   prüfen: Anzahl Vorgänge je Prozess, Aktivitäten je Prozess, Zeitraum.
3. `02_process_model.sql` mit den echten Soll-Prozessen, Kontrollen, Regeln, Verantwortlichen
   und Layout füllen und ausführen.
4. `03_views.sql` ausführen. Prüfen, welche Befunde entstehen, und mit den Process Ownern
   klären: **echte Governance-Lücke oder fehlender Eintrag im Soll-Modell?**
5. Regel für laufende Vorgänge einbauen (Klärungspunkt 5), konsistent in den Views.
6. Datasets 04–07 im Dashboard anlegen. Parameter `:process` und `:domain` mit Standardwerten
   anlegen.
7. Dashboard laut Abschnitt 8 aufbauen. Custom Viz mit `process_graph.vl.json`; Felder **ohne
   Aggregation**: `row_type, id, src, tgt, cases, median_wait_h, x, y, w, h, seq, shape, node_kind,
   conformance, is_control, finding_type`.
8. SQL Alert aus `08_…` einrichten, täglich, Empfänger je Process Owner.
9. Betrieb:
   - Bei großem Log `v_transitions` und `v_findings` als **materialisierte Tabellen** per Job
     (z. B. stündlich oder täglich) statt Views.
   - Den fertigen Dashboard-Stand als `.lvdash.json` **exportieren** und versionieren. Der Export
     ist die verlässliche Formatquelle.
10. Optional: `process_mining.lvdash.json` importieren. In der Import-Version hat
    `findings_summary` keinen `:domain`-Parameter.

---

## 10. Abnahmekriterien

### Mit den Beispieldaten (`01` + `02`)

Diese Werte müssen exakt herauskommen:

| Prüfung | Erwartet |
|---|---|
| Vorgänge | 1.000 (AR 500, DC 300, DP 200) |
| Prozesskonformität | gesamt 74,5 % · AR 72,0 % · DC 78,3 % · DP 75,0 % |
| Governance-konform | gesamt 68,5 % · AR 63,6 % · DC 74,3 % · DP 72,0 % |
| Vorgänge mit kritischem Befund | 251 (AR 123, DC 73, DP 55) |
| Kontrolle umgangen / Funktionstrennung / Frist | AR 105 / 23 / 42 · DC 65 / 10 / 6 · DP 50 / 6 / 1 |
| `findings_summary` | 14 Zeilen; 7 aktive kritische; genau 1 `neu`: DP „Data Contract verknüpft, Qualitätsprüfung, Freigabe Data Owner umgangen“ (10 Vorgänge, erstmals 21.05.2026) |
| Weitere Status | AR „Prüfung Security umgangen“: 90 Vorgänge, erstmals 02.04.2026, 29,2 % der letzten 4 Wochen, „tritt weiterhin auf“. DC „Schema validiert umgangen“: 25, zuletzt 06.04.2026, „nicht mehr aufgetreten“ |
| Konformität je Monat (AR) | Jan 90,0 % → Apr 60,6 % → Jun 58,9 % |
| Prozessgraph AR | 7 Knoten; rot: Start → Berechtigung erteilt (15), Prüfung Data Owner → Berechtigung erteilt (90); orange: Prüfung Data Owner → Beantragt (35) |
| Prozessgraph DC | 12 Knoten; rot: Entwurf → Review Data Owner (25), Änderung beantragt → Neue Version aktiv (40) |
| Prozessgraph DP | 9 Knoten; rot: Angelegt → Veröffentlicht (10), Data Contract verknüpft → Freigabe (20), Metadaten → Qualitätsprüfung (20); grau als erlaubter Rücksprung: Qualitätsprüfung → Metadaten (25) |
| Alarm | 5 Zeilen, davon 1 mit `is_new = true` (DP, s. o.) |
| Parameter | `:domain = 'Finance'` liefert kleinere, gültige Ergebnisse ohne Fehler |

### Allgemein

* Alle Views und Datasets laufen im SQL Warehouse ohne Fehler.
* Custom Viz rendert für jeden Prozess ohne Konsolenfehler. Tooltips funktionieren, helles und
  dunkles Theme sind lesbar.
* **Ein neuer Prozess oder eine Prozessänderung erfordert nur Einträge in `02_process_model.sql`**
  (und ggf. im Status-Mapping der Event-View), keine Änderung an Views, Datasets oder Dashboard.
* Der Alarm erreicht den Process Owner bei einem neuen kritischen Befund.
* Keine Databricks App.

---

## 11. Risiken und Fallstricke

* **Datenqualität des Audit-Logs:** fehlende oder doppelte Events, gleiche Zeitstempel, technische
  Statuswechsel. Gegenmaßnahme: `step_no` als Tie-Breaker, technische Events in der View
  herausfiltern, Status-Mapping pflegen.
* **Laufende Vorgänge** verfälschen „Kein gültiger Abschluss“ und Konformität (Klärungspunkt 5).
* **Technische Accounts** (`system`, Service Principals) können Funktionstrennungs-Regeln
  scheinbar erfüllen oder verletzen. Je Regel festlegen, wie sie zählen.
* **Versionierung** (Data Contracts): Ist ein Vorgang ein Contract über alle Versionen oder eine
  Änderung? Die Wahl beeinflusst Rücksprünge und Fristen.
* **`.lvdash.json` ist undokumentiert** und **Custom Viz ist Public Preview.** Nach manuellem
  Aufbau den echten Export versionieren.
* **Feldnamen in Custom Viz** müssen exakt stimmen und dürfen nicht aggregiert sein.
* **Personenbezug:** `actor` und `initiator` sind personenbezogene Daten. Zugriff auf Dashboard
  und Datasets beschränken und ggf. pseudonymisieren.

---

## 12. Mögliche Erweiterungen (nicht Teil des ersten Auftrags)

* Weitere Prozesse: **Change Approval**, **kanonische Datenmodelle**, Applikations-Onboarding,
  **Rezertifizierung und Entzug von Zugriffen** (wichtig für Audits).
* Fristverletzungen für **offene** Vorgänge; Erinnerung vor Fristablauf.
* **Verknüpfung mit Application Monitoring:** gemeinsame Vorgangs- oder Trace-ID in Workflow-Events
  und Applikations-Logs. Dann lässt sich unterscheiden, ob ein fehlender Schritt eine Lücke in
  der Applikation ist oder ein technischer Fehler.
* **Audit-Export** je Befund (Vorgänge, Personen, Zeitstempel) als Nachweis.
* Ticket automatisch anlegen (z. B. Jira) bei neuem kritischem Befund.

---

## 13. Lokal testen ohne Workspace (optional)

* **SQL:** PySpark 4.x; `main.data_manager_pm.` durch ein lokales Schema ersetzen, `CREATE OR
  REPLACE TABLE` durch `CREATE TABLE`; Parameter über
  `spark.sql(q, args={"process": "Access Request", "domain": "Alle"})`.
* **Vega-Lite:** `npm i vega vega-lite` (v5 und v6). `data` durch `{"values": [...]}` ersetzen,
  Höhe = Breite × (frame-y / 800), mit `vl.compile` + `new vega.View(...).toSVG()` rendern.
  Warnungen müssen leer sein.
* **Gesamtbild:** `dashboard.html` öffnen. Die Datei funktioniert offline; `#Data%20Contract` in
  der URL öffnet direkt die Detailseite.
