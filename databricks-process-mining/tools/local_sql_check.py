#!/usr/bin/env python3
"""
Lokale Abnahmeprüfung der SQL-Logik ohne Databricks-Workspace.

Führt 01–10 mit lokalem Apache Spark aus (Katalog main.data_manager_pm -> lokales Schema,
CREATE OR REPLACE TABLE -> CREATE TABLE), prüft die Abnahmewerte aus IMPLEMENTATION_SPEC.md
Abschnitt 10 und schreibt die Graph-Daten je Prozess nach build/graph_<prozess>.json
(Eingabe für tools/check_vega_spec.mjs).

Voraussetzungen: Java 17+, pip install pyspark==4.0.1
Aufruf (im Ordner databricks-process-mining):  python tools/local_sql_check.py
Exit-Code 0 = alle Prüfungen bestanden.

11_ und 12_ sind Databricks-spezifisch (read_files, STREAMING TABLE) und werden hier nicht geprüft.
"""
from __future__ import annotations

import json
import re
import sys
import tempfile
from decimal import Decimal
from pathlib import Path

from pyspark.sql import SparkSession

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "build"
PROCS = ["Access Request", "Data Contract", "Data Product"]
failures: list[str] = []


def expect(name: str, actual, expected) -> None:
    if isinstance(actual, Decimal):
        actual = float(actual)
    ok = actual == expected
    print(f"  [{'OK ' if ok else 'ERR'}] {name}: {actual!r}" + ("" if ok else f"  (erwartet {expected!r})"))
    if not ok:
        failures.append(name)


def load(spark: SparkSession, f: str) -> list[str]:
    s = (ROOT / f).read_text(encoding="utf-8")
    s = s.replace("main.data_manager_pm", "data_manager_pm").replace("CREATE OR REPLACE TABLE", "CREATE TABLE")
    return [x for x in re.split(r";\s*\n", s) if re.sub(r"--.*", "", x).strip()]


def main() -> int:
    wh = tempfile.mkdtemp(prefix="dm_wh_")
    spark = (SparkSession.builder.master("local[2]").appName("dm-local-sql-check")
             .config("spark.ui.enabled", "false").config("spark.driver.memory", "6g")
             .config("spark.sql.shuffle.partitions", "4").config("spark.sql.warehouse.dir", wh).getOrCreate())
    spark.sparkContext.setLogLevel("ERROR")
    for f in ["01_sample_event_log.sql", "02_process_model.sql", "03_views.sql"]:
        for st in load(spark, f):
            spark.sql(st)
    q = lambda f, **a: spark.sql(load(spark, f)[0], args=a or None)
    rows = lambda df: [r.asDict() for r in df.collect()]

    print("Vorgänge und Konformität")
    q("05_ds_case_conformance.sql").createOrReplaceTempView("cc")
    k = {r["process"]: r for r in rows(spark.sql(
        "select process, count(*) n, round(avg(is_conformant)*100,1) rate, round(avg(is_compliant)*100,1) comp, "
        "sum(has_critical) crit, sum(has_control_bypass) bypass, sum(has_sod_violation) sod, sum(has_sla_breach) sla "
        "from cc group by process"))}
    t = rows(spark.sql("select count(*) n, round(avg(is_conformant)*100,1) rate, round(avg(is_compliant)*100,1) comp, "
                       "sum(has_critical) crit from cc"))[0]
    expect("Vorgänge gesamt", t["n"], 1000)
    expect("Prozesskonformität gesamt", float(t["rate"]), 74.5)
    expect("Governance-konform gesamt", float(t["comp"]), 68.5)
    expect("Vorgänge mit kritischem Befund", t["crit"], 251)
    for p, vals in {"Access Request": (500, 72.0, 63.6, 123, 105, 23, 42),
                    "Data Contract": (300, 78.3, 74.3, 73, 65, 10, 6),
                    "Data Product": (200, 75.0, 72.0, 55, 50, 6, 1)}.items():
        r = k[p]
        expect(f"{p}: n/rate/comp/crit/bypass/sod/sla",
               (r["n"], float(r["rate"]), float(r["comp"]), r["crit"], r["bypass"], r["sod"], r["sla"]), vals)
    m = rows(spark.sql("select date_format(date_trunc('MONTH', case_start), 'yyyy-MM') m, round(avg(is_conformant)*100,1) r "
                       "from cc where process = 'Access Request' and case_start < '2026-07-01' group by 1 order by 1"))
    expect("AR Konformität Jan/Apr/Jun", (float(m[0]["r"]), float(m[3]["r"]), float(m[5]["r"])), (90.0, 60.6, 58.9))

    print("Befunde (findings_summary)")
    summ = rows(q("07_ds_findings_summary.sql", domain="Alle"))
    expect("Zeilen", len(summ), 14)
    expect("aktive kritische", sum(s["severity"] == "kritisch" and s["status"] != "nicht mehr aufgetreten" for s in summ), 7)
    new = [s for s in summ if s["status"] == "neu"]
    expect("neue Befunde", [(s["process"], s["finding"], s["cases"], str(s["first_seen"])) for s in new],
           [("Data Product", "Data Contract verknüpft, Qualitätsprüfung, Freigabe Data Owner umgangen", 10, "2026-05-21")])
    sec = next(s for s in summ if s["finding"] == "Prüfung Security umgangen")
    expect("AR Security umgangen", (sec["cases"], str(sec["first_seen"]), float(sec["pct_last_4w"]), sec["status"],
                                    sec["channels"], sec["first_release"], sec["system_status"]),
           (90, "2026-04-02", 29.2, "tritt weiterhin auf", "system", "2.3", "vom System erlaubt"))
    sch = next(s for s in summ if s["finding"] == "Schema validiert umgangen")
    expect("DC Schema validiert umgangen", (sch["cases"], str(sch["last_seen"]), sch["status"]), (25, "2026-03-30", "nicht mehr aufgetreten"))
    expect("Parameter domain=Finance läuft", q("07_ds_findings_summary.sql", domain="Finance").count() > 0, True)

    print("Alarm")
    alert = rows(q("08_alert_critical_findings.sql"))
    expect("Zeilen / davon neu", (len(alert), sum(bool(a["is_new"]) for a in alert)), (5, 1))

    print("System-Konformität")
    sysc = rows(q("09_ds_system_conformance.sql"))
    cat = lambda c: sorted((s["process"], s["transition"]) for s in sysc if s["system_category"] == c)
    expect("Übergänge gesamt / konform", (len(sysc), sum(s["system_category"] == "Konform" for s in sysc)), (42, 31))
    expect("Übergänge System / Soll", (sum(bool(s["in_system"]) for s in sysc), sum(bool(s["in_soll"]) for s in sysc)), (38, 32))
    expect("außerhalb des Workflows", cat("Umgehung außerhalb des Workflows"),
           [("Access Request", "▶ Start → Berechtigung erteilt"), ("Data Product", "Angelegt → Veröffentlicht")])
    expect("latent", cat("System lässt mehr zu – latent"),
           [("Access Request", "Beantragt → Berechtigung erteilt"), ("Data Product", "Metadaten erfasst → Freigabe Data Owner")])
    expect("Soll nicht implementiert", cat("Soll-Schritt nicht implementiert"), [("Data Contract", "Review Änderung → Verworfen")])
    expect("genutzt (Anzahl)", len(cat("System lässt mehr zu – genutzt")), 5)
    rej = rows(q("10_ds_rejected_attempts.sql"))
    expect("abgewiesene Versuche", len(rej), 25)

    print("Prozessgraph")
    BUILD.mkdir(exist_ok=True)
    for p, nodes in {"Access Request": 7, "Data Contract": 12, "Data Product": 9}.items():
        g = rows(q("04_ds_process_graph.sql", process=p, domain="Alle"))
        expect(f"{p}: Knoten", sum(r["row_type"] == "node" for r in g), nodes)
        latent = sorted(r["id"] for r in g if r["row_type"] == "arrow" and r["conformance"] == "latent")
        expect(f"{p}: latente Kanten", latent, {"Access Request": ["Beantragt → Berechtigung erteilt"], "Data Contract": [],
                                                "Data Product": ["Metadaten erfasst → Freigabe Data Owner"]}[p])
        out = BUILD / f"graph_{p.lower().replace(' ', '_')}.json"
        out.write_text(json.dumps(g, ensure_ascii=False, default=lambda v: float(v) if isinstance(v, Decimal) else str(v)),
                       encoding="utf-8")
    expect("Graph mit domain=Finance läuft", q("04_ds_process_graph.sql", process="Access Request", domain="Finance").count() > 0, True)

    print(f"\n{'ALLE PRÜFUNGEN BESTANDEN' if not failures else str(len(failures)) + ' FEHLGESCHLAGEN: ' + ', '.join(failures)}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
