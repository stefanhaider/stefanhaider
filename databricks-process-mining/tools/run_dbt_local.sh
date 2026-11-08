#!/usr/bin/env bash
# Baut das Data Product (dbt) lokal mit Apache Spark + Delta Lake und Beispieldaten – inkl. aller Tests.
# Aufruf im Ordner databricks-process-mining:  bash tools/run_dbt_local.sh [weitere dbt-Argumente]
# Voraussetzungen: Java 17+, pip install "dbt-core>=1.10" "dbt-spark[session]>=1.9" pyspark==4.0.1
# Die Delta-JARs (4.0.0) werden beim ersten Lauf nach tools/.jars geladen.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JARS="$ROOT/tools/.jars"; WH="$ROOT/build/spark-warehouse"
mkdir -p "$JARS" "$WH"
for a in delta-spark_2.13 delta-storage; do
  [ -f "$JARS/$a-4.0.0.jar" ] || curl -sSfL -o "$JARS/$a-4.0.0.jar" "https://repo1.maven.org/maven2/io/delta/$a/4.0.0/$a-4.0.0.jar"
done
export PYSPARK_SUBMIT_ARGS="--driver-memory 6g \
 --jars $JARS/delta-spark_2.13-4.0.0.jar,$JARS/delta-storage-4.0.0.jar \
 --conf spark.sql.extensions=io.delta.sql.DeltaSparkSessionExtension \
 --conf spark.sql.catalog.spark_catalog=org.apache.spark.sql.delta.catalog.DeltaCatalog \
 --conf spark.sql.catalogImplementation=hive \
 --conf spark.sql.warehouse.dir=$WH \
 --conf spark.driver.extraJavaOptions=-Dderby.system.home=$WH \
 --conf spark.sql.shuffle.partitions=4 --conf spark.ui.enabled=false pyspark-shell"
cd "$ROOT/process_monitoring/dbt"
DBT=${DBT:-dbt}
$DBT build --profiles-dir profiles --target local --vars '{use_sample_data: true}' "$@"
