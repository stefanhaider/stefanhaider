#!/usr/bin/env python3
"""
Referenz-Implementierung für den Data Manager (sprachneutral übertragbar):

  1. EINE zentrale Status-Maschine je Objekttyp (Single Source of Truth im Code)
  2. Jeder Statuswechsel läuft durch transition() – egal ob UI, API, Admin oder Batch
  3. transition() schreibt GENAU EIN Event nach EVENT_STANDARD.md, auch für abgewiesene Versuche
  4. Events gehen über eine Outbox-Tabelle in derselben DB-Transaktion wie der Statuswechsel
     (kein Event ohne Statuswechsel, kein Statuswechsel ohne Event)
  5. export_workflow_definition() erzeugt config/workflow_definition.json für den CI-Check

Ausführen (Demo mit SQLite im Speicher):  python examples/event_writer_example.py
"""
from __future__ import annotations

import json
import sqlite3
import uuid
from dataclasses import dataclass, field
from datetime import datetime, timezone

APP_VERSION = "2.5"
WORKFLOW_VERSION = "2.5"
CHANNELS = {"ui", "api", "admin_api", "batch", "system", "migration"}


@dataclass
class Workflow:
    """Erlaubte Statusübergänge eines Objekttyps. '▶ Start' = Anlage, '■ Ende' = Abschluss."""
    process: str
    transitions: dict[tuple[str, str], dict] = field(default_factory=dict)
    terminal: set[str] = field(default_factory=set)

    def allow(self, src: str, tgt: str, since_release: str = "2.2", note: str = "Standard-Workflow",
              channels: set[str] | None = None) -> "Workflow":
        self.transitions[(src, tgt)] = {"since_release": since_release, "note": note,
                                        "channels": sorted(channels) if channels else None}
        return self


ACCESS_REQUEST = (
    Workflow("Access Request", terminal={"Berechtigung erteilt", "Abgelehnt"})
    .allow("▶ Start", "Beantragt")
    .allow("Beantragt", "Prüfung Data Owner")
    .allow("Prüfung Data Owner", "Prüfung Security")
    .allow("Prüfung Data Owner", "Abgelehnt")
    .allow("Prüfung Security", "Berechtigung erteilt")
    .allow("Prüfung Security", "Abgelehnt")
)


class TransitionRejected(Exception):
    pass


class DataManager:
    def __init__(self, db: sqlite3.Connection, workflows: list[Workflow]):
        self.db = db
        self.workflows = {w.process: w for w in workflows}
        db.executescript("""
            CREATE TABLE IF NOT EXISTS objects (case_id TEXT PRIMARY KEY, process TEXT, status TEXT, domain TEXT);
            CREATE TABLE IF NOT EXISTS event_outbox (event_id TEXT PRIMARY KEY, payload TEXT, published INTEGER DEFAULT 0);
        """)

    # ---- der EINZIGE Weg, einen Status zu ändern -------------------------------------------
    def transition(self, process: str, case_id: str, to_status: str, *, actor: str, channel: str,
                   domain: str | None = None, trace_id: str | None = None, object_version: str | None = None,
                   reason: str | None = None) -> dict:
        assert channel in CHANNELS, f"unbekannter Kanal {channel}"
        wf = self.workflows[process]
        row = self.db.execute("SELECT status, domain FROM objects WHERE case_id = ?", (case_id,)).fetchone()
        from_status = row[0] if row else "▶ Start"
        domain = domain or (row[1] if row else None)
        rule = wf.transitions.get((from_status, to_status))
        allowed = rule is not None and (rule["channels"] is None or channel in rule["channels"])

        event = {
            "event_id": str(uuid.uuid4()),
            "event_type": "transition" if allowed else "rejected",
            "process": process,
            "case_id": case_id,
            "object_version": object_version,
            "domain": domain,
            "from_activity": None if from_status == "▶ Start" else from_status,
            "activity": to_status,
            "actor": actor,
            "channel": channel,
            "app_version": APP_VERSION,
            "workflow_version": WORKFLOW_VERSION,
            "trace_id": trace_id or str(uuid.uuid4()),
            "event_ts": datetime.now(timezone.utc).isoformat(timespec="milliseconds"),
            "reason": reason if allowed else f"Übergang {from_status} → {to_status} über '{channel}' nicht erlaubt",
        }
        with self.db:  # eine Transaktion: Status + Outbox
            if allowed:
                if row:
                    self.db.execute("UPDATE objects SET status = ? WHERE case_id = ?", (to_status, case_id))
                else:
                    self.db.execute("INSERT INTO objects VALUES (?, ?, ?, ?)", (case_id, process, to_status, domain))
            self.db.execute("INSERT INTO event_outbox (event_id, payload) VALUES (?, ?)",
                            (event["event_id"], json.dumps(event, ensure_ascii=False)))
        if not allowed:
            raise TransitionRejected(event["reason"])
        return event

    # ---- Export für den CI-Check ------------------------------------------------------------
    def export_workflow_definition(self) -> dict:
        return {
            "application": "Data Manager",
            "release": APP_VERSION,
            "exported_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
            "workflows": [
                {"process": w.process,
                 "transitions": [{"from": s, "to": t, **r} for (s, t), r in w.transitions.items()]
                                + [{"from": s, "to": "■ Ende", "since_release": "2.2", "note": "Abschluss",
                                    "channels": None} for s in sorted(w.terminal)]}
                for w in self.workflows.values()
            ],
        }


if __name__ == "__main__":
    dm = DataManager(sqlite3.connect(":memory:"), [ACCESS_REQUEST])
    dm.transition("Access Request", "AR-1", "Beantragt", actor="user_017", channel="ui", domain="Finance")
    dm.transition("Access Request", "AR-1", "Prüfung Data Owner", actor="owner_03", channel="ui")
    try:  # Security-Prüfung überspringen -> wird abgewiesen und trotzdem protokolliert
        dm.transition("Access Request", "AR-1", "Berechtigung erteilt", actor="admin_01", channel="admin_api")
    except TransitionRejected as e:
        print("abgewiesen:", e)
    for (payload,) in dm.db.execute("SELECT payload FROM event_outbox"):
        e = json.loads(payload)
        print(f"{e['event_type']:10} {e['from_activity'] or '▶ Start':20} → {e['activity']:20} {e['channel']:9} {e['actor']}")
    print(json.dumps(dm.export_workflow_definition(), ensure_ascii=False)[:160], "...")
