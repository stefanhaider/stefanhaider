"""Export der Status-Maschine als workflow_definition.json (für CI-Check und Databricks).

    dm-export-workflow --out build/workflow_definition.json
    python -m datamanager_governance.export --out build/workflow_definition.json
"""
from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime, timezone

from .events import END
from .state_machine import Workflow
from .workflows import APP_VERSION, WORKFLOWS


def workflow_definition(workflows: list[Workflow] = WORKFLOWS, release: str = APP_VERSION,
                        exported_at: str | None = None) -> dict:
    def entry(src, tgt, rule):
        e = {"from": src, "to": tgt, "since_release": rule.since_release, "note": rule.note}
        if rule.channels:
            e["channels"] = list(rule.channels)
        return e
    return {
        "application": "Data Manager",
        "release": release,
        "exported_at": exported_at or datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z"),
        "workflows": [
            {"process": w.process,
             "transitions": [entry(s, t, r) for (s, t), r in w.transitions.items()]
                            + [entry(s, END, r) for s, r in w.terminal.items()]}
            for w in workflows
        ],
    }


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="Status-Maschine des Data Managers exportieren")
    ap.add_argument("--out", help="Zieldatei (Standard: stdout)")
    ap.add_argument("--exported-at", help="festes Exportdatum (für reproduzierbare Builds)")
    args = ap.parse_args(argv)
    text = json.dumps(workflow_definition(exported_at=args.exported_at), ensure_ascii=False, indent=2) + "\n"
    if args.out:
        with open(args.out, "w", encoding="utf-8") as f:
            f.write(text)
    else:
        sys.stdout.write(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
