"""Stammdaten fürs Prozess-Monitoring nach PostgreSQL schreiben (beim Deploy des Data Managers).

    dm-sync-governance --dsn postgresql://... --model governance/governance_model.json

Schreibt idempotent, in EINER Transaktion:
  * governance.app_release          – alle Releases aus workflows.RELEASES
  * governance.workflow_transition  – Status-Maschine des AKTUELLEN Releases (ersetzt nur dieses Release;
                                      ältere Releases bleiben -> Historie für Databricks)
  * governance.process_catalog      – Prozesse und Process Owner aus dem Governance-Modell
  * governance.process_model_*      – Soll-Modell-Version (unveränderlich; neue Version wird angelegt und
                                      als aktuell markiert, bestehende Versionen werden nie geändert)
  * governance.governance_rule      – Regeln der Modell-Version

Voraussetzung: 001_process_event.sql und 002_governance_model.sql sind angewendet.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from .events import END
from .workflows import APP_VERSION, RELEASES, WORKFLOWS


def sync(conn, model: dict, workflows=WORKFLOWS, releases=RELEASES, app_version: str = APP_VERSION) -> dict:
    stats = {"releases": 0, "workflow_transitions": 0, "model_version_created": False}
    with conn.transaction():
        for version, released_at, notes in releases:
            conn.execute("INSERT INTO governance.app_release (version, released_at, notes) VALUES (%s, %s, %s) "
                         "ON CONFLICT (version) DO UPDATE SET released_at = EXCLUDED.released_at, notes = EXCLUDED.notes",
                         (version, released_at, notes))
            stats["releases"] += 1

        conn.execute("DELETE FROM governance.workflow_transition WHERE release = %s", (app_version,))
        for w in workflows:
            rows = [(s, t, r) for (s, t), r in w.transitions.items()] + [(s, END, r) for s, r in w.terminal.items()]
            for src, tgt, rule in rows:
                conn.execute("INSERT INTO governance.workflow_transition VALUES (%s, %s, %s, %s, %s, %s, %s)",
                             (app_version, w.process, src, tgt, rule.since_release, rule.note,
                              ",".join(rule.channels) if rule.channels else None))
                stats["workflow_transitions"] += 1

        for p in model["processes"]:
            conn.execute("INSERT INTO governance.process_catalog VALUES (%s, %s, %s) ON CONFLICT (process) "
                         "DO UPDATE SET owner = EXCLUDED.owner, description = EXCLUDED.description",
                         (p["process"], p["owner"], p.get("description")))

        mv = model["model_version"]
        exists = conn.execute("SELECT 1 FROM governance.process_model_version WHERE model_version = %s", (mv,)).fetchone()
        if not exists:
            conn.execute("INSERT INTO governance.process_model_version VALUES (%s, %s, %s, false)",
                         (mv, model["approved_by"], model["approved_at"]))
            for p in model["processes"]:
                for a in p["activities"]:
                    conn.execute("INSERT INTO governance.process_model_activity VALUES (%s, %s, %s, %s, %s, %s)",
                                 (mv, p["process"], a["name"], a["step_order"], a["is_terminal"], a["is_control"]))
                for src, tgt in p["allowed_transitions"]:
                    conn.execute("INSERT INTO governance.process_model_transition VALUES (%s, %s, %s, %s)",
                                 (mv, p["process"], src, tgt))
                for r in p.get("rules", []):
                    conn.execute("INSERT INTO governance.governance_rule VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)",
                                 (mv, p["process"], r["rule_id"], r["rule_type"], r["activity_a"], r["activity_b"],
                                  r.get("max_hours"), r.get("description"), r["severity"]))
            stats["model_version_created"] = True
        conn.execute("UPDATE governance.process_model_version SET is_current = false WHERE is_current AND model_version <> %s", (mv,))
        conn.execute("UPDATE governance.process_model_version SET is_current = true WHERE model_version = %s", (mv,))
    return stats


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="Stammdaten fürs Prozess-Monitoring nach PostgreSQL schreiben")
    ap.add_argument("--dsn", required=True)
    ap.add_argument("--model", default="governance/governance_model.json")
    args = ap.parse_args(argv)
    import psycopg
    model = json.loads(Path(args.model).read_text(encoding="utf-8"))
    with psycopg.connect(args.dsn) as conn:
        print(json.dumps(sync(conn, model), ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
