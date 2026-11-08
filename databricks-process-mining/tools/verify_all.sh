#!/usr/bin/env bash
# Führt alle lokalen Prüfungen aus. Aufruf im Ordner databricks-process-mining:  bash tools/verify_all.sh
# Voraussetzungen: Python 3.10+, Java 17+, Node 18+; Pakete siehe AGENTS.md Abschnitt 4.
# Optional: DM_TEST_PG_DSN=postgresql://user@host:5432/testdb (UTF-8, wird verändert!) für die PostgreSQL-Tests.
# Schritte, deren Werkzeug fehlt, werden als ÜBERSPRUNGEN gemeldet (nicht als bestanden).
set -u
cd "$(dirname "$0")/.."
PY=${PYTHON:-python3}; DBT=${DBT:-dbt}
fail=0; skip=0
step() { echo; echo "=== $1"; }

step "1/4 Data Manager: Python-Paket (pytest; mit DM_TEST_PG_DSN auch gegen PostgreSQL)"
if $PY -c "import pytest" 2>/dev/null; then
  [ -n "${DM_TEST_PG_DSN:-}" ] || { echo "Hinweis: DM_TEST_PG_DSN nicht gesetzt – PostgreSQL-Tests werden übersprungen"; skip=1; }
  out=$(cd data_manager/python && PYTHONPATH=src $PY -m pytest -q 2>&1); rc=$?
  echo "$out" | tail -2; [ $rc -eq 0 ] || fail=1
else echo "ÜBERSPRUNGEN: pip install -e ./data_manager/python[test]"; skip=1; fi

step "2/4 Data Manager: CI-Check (erwartet 8 Befunde, 6 blockierend, Exit-Code 1)"
out=$(cd data_manager && PYTHONPATH=python/src $PY -m datamanager_governance.conformance --today 2026-07-06); rc=$?
echo "$out" | tail -1
if [ $rc -eq 1 ] && echo "$out" | grep -q "8 Befunde, davon 6 blockierend"; then echo "OK"; else echo "FEHLER (rc=$rc)"; fail=1; fi

step "3/4 Data Product: dbt build mit Beispieldaten (lokal Spark + Delta, inkl. Abnahmetests)"
if command -v "$DBT" >/dev/null && command -v java >/dev/null; then
  rm -rf build/spark-warehouse
  out=$(DBT=$DBT bash tools/run_dbt_local.sh 2>&1); rc=$?
  echo "$out" | sed 's/\x1b\[[0-9;]*m//g' | grep -E "(ERROR|FAIL) |Done\." | sed 's/^[0-9:]* *//'
  [ $rc -eq 0 ] || fail=1
else echo "ÜBERSPRUNGEN: pip install 'dbt-core>=1.10' 'dbt-spark[session]>=1.9' pyspark==4.0.1; Java 17+"; skip=1; fi

step "4/4 Dashboard: Vega-Lite-Spezifikation mit mart_process_graph rendern (ohne Warnungen)"
if command -v node >/dev/null && [ -d tools/node_modules ] && [ -d build/spark-warehouse/process_monitoring.db/mart_process_graph ]; then
  $PY tools/export_graph_json.py 2>/dev/null | grep graph_ || true
  (cd tools && node check_vega_spec.mjs) || fail=1
else echo "ÜBERSPRUNGEN: cd tools && npm install; Schritt 3 muss vorher gelaufen sein"; skip=1; fi

echo
if [ $fail -ne 0 ]; then echo "ERGEBNIS: FEHLER"; exit 1; fi
if [ $skip -ne 0 ]; then echo "ERGEBNIS: bestanden, aber Schritte übersprungen"; exit 0; fi
echo "ERGEBNIS: ALLES BESTANDEN"
