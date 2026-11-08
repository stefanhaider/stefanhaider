#!/usr/bin/env python3
"""Exportiert mart_process_graph (domain_scope 'Alle') aus dem lokalen dbt-Lauf nach build/graph_<prozess>.json
als Eingabe für tools/check_vega_spec.mjs.  Vorher: bash tools/run_dbt_local.sh
"""
import json
from decimal import Decimal
from pathlib import Path

from pyspark.sql import SparkSession

ROOT = Path(__file__).resolve().parents[1]
table = ROOT / "build/spark-warehouse/process_monitoring.db/mart_process_graph"
jars = ",".join(str(p) for p in sorted((ROOT / "tools/.jars").glob("*.jar")))
spark = (SparkSession.builder.master("local[2]").config("spark.ui.enabled", "false").config("spark.jars", jars)
         .config("spark.sql.extensions", "io.delta.sql.DeltaSparkSessionExtension")
         .config("spark.sql.catalog.spark_catalog", "org.apache.spark.sql.delta.catalog.DeltaCatalog").getOrCreate())
spark.sparkContext.setLogLevel("ERROR")
df = spark.read.format("delta").load(str(table)).where("domain_scope = 'Alle'")
for p in [r[0] for r in df.select("process").distinct().collect()]:
    rows = [r.asDict() for r in df.where(df.process == p).collect()]
    out = ROOT / "build" / f"graph_{p.lower().replace(' ', '_')}.json"
    out.write_text(json.dumps(rows, ensure_ascii=False, default=lambda v: float(v) if isinstance(v, Decimal) else str(v)), encoding="utf-8")
    print(f"{out.name}: {len(rows)} Zeilen")
