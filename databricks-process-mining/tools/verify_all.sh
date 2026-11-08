#!/usr/bin/env bash
# Führt alle lokalen Prüfungen aus. Aufruf im Ordner databricks-process-mining:  bash tools/verify_all.sh
# Voraussetzungen: Python 3.10+, Java 17+ (für Spark), Node 18+ (für Vega-Lite).
# Schritte, deren Werkzeug fehlt, werden als ÜBERSPRUNGEN gemeldet (nicht als bestanden).
set -u
cd "$(dirname "$0")/.."
PY=${PYTHON:-python3}
fail=0; skip=0
step() { echo; echo "=== $1"; }

step "1/4 Python-Paket: Tests (mit DM_TEST_PG_DSN zusätzlich gegen PostgreSQL)"
if $PY -c "import pytest" 2>/dev/null; then
  [ -n "${DM_TEST_PG_DSN:-}" ] || echo "Hinweis: DM_TEST_PG_DSN nicht gesetzt – PostgreSQL-Tests werden übersprungen"
  pyout=$(cd python && PYTHONPATH=src $PY -m pytest -q 2>&1); rc=$?
  echo "$pyout" | tail -2; [ $rc -eq 0 ] || fail=1
  [ -n "${DM_TEST_PG_DSN:-}" ] || skip=1
else echo "ÜBERSPRUNGEN: pip install -e ./python[test]"; skip=1; fi

step "2/4 CI-Check: erwartet 8 Befunde, 6 blockierend, Exit-Code 1"
out=$(PYTHONPATH=python/src $PY -m datamanager_governance.conformance --model config/governance_model.json \
      --accepted ci/accepted_deviations.json --today 2026-07-06); rc=$?
echo "$out" | tail -1
if [ $rc -eq 1 ] && echo "$out" | grep -q "8 Befunde, davon 6 blockierend"; then echo "OK"; else echo "FEHLER (rc=$rc)"; fail=1; fi

step "3/4 SQL-Logik mit lokalem Spark (Abnahmewerte)"
if $PY -c "import pyspark" 2>/dev/null && command -v java >/dev/null; then
  sqlout=$($PY tools/local_sql_check.py 2>/dev/null); rc=$?
  echo "$sqlout" | grep -E "ERR|BESTANDEN|FEHLGESCHLAGEN" || true
  [ $rc -eq 0 ] || fail=1
else echo "ÜBERSPRUNGEN: pip install pyspark==4.0.1 und Java 17+"; skip=1; fi

step "4/4 Vega-Lite-Spezifikation rendern (ohne Warnungen)"
if command -v node >/dev/null && [ -d tools/node_modules ] && ls build/graph_*.json >/dev/null 2>&1; then
  (cd tools && node check_vega_spec.mjs) || fail=1
else echo "ÜBERSPRUNGEN: cd tools && npm install; Schritt 3 muss vorher gelaufen sein"; skip=1; fi

echo
if [ $fail -ne 0 ]; then echo "ERGEBNIS: FEHLER"; exit 1; fi
if [ $skip -ne 0 ]; then echo "ERGEBNIS: bestanden, aber Schritte übersprungen"; exit 0; fi
echo "ERGEBNIS: ALLES BESTANDEN"
