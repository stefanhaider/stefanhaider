#!/usr/bin/env python3
"""
Demo: so nutzt der Data Manager das Paket datamanager_governance (python/).

  * zentrale Status-Maschine (datamanager_governance.workflows) – einziger Weg für Statuswechsel
  * Event + Statuswechsel in EINER Transaktion (Outbox)
  * abgewiesene Versuche über reject_sink in eigener Transaktion (überleben den Rollback)
  * Publisher: Outbox -> JSONL (lokal oder Unity-Catalog-Volume) -> 12_ingest_events.sql
  * Export der Status-Maschine für den CI-Check

Ausführen:  pip install ./python   &&   python examples/event_writer_example.py
(ohne Installation: PYTHONPATH=python/src python examples/event_writer_example.py)
"""
import json
import sqlite3
import tempfile
from pathlib import Path

from datamanager_governance.export import workflow_definition
from datamanager_governance.outbox import DbApiOutbox, autonomous_sink
from datamanager_governance.publisher import publish
from datamanager_governance.state_machine import StateMachine, TransitionRejected
from datamanager_governance.workflows import APP_VERSION, WORKFLOWS


class ObjectRepository:
    """In der echten Anwendung: ORM-Repository der jeweiligen Objekte (Access Request, Contract, ...)."""
    def get_status(self, process, case_id, conn):
        row = conn.execute("SELECT status FROM objects WHERE process=? AND case_id=?", (process, case_id)).fetchone()
        return row[0] if row else None

    def set_status(self, process, case_id, status, conn, **attrs):
        conn.execute("INSERT INTO objects VALUES (?,?,?,?) ON CONFLICT(process, case_id) DO UPDATE SET status=excluded.status",
                     (process, case_id, status, attrs.get("domain")))


def main():
    work = Path(tempfile.mkdtemp())
    db = work / "datamanager.sqlite"
    conn = sqlite3.connect(db)
    conn.execute("CREATE TABLE objects (process TEXT, case_id TEXT, status TEXT, domain TEXT, PRIMARY KEY (process, case_id))")
    DbApiOutbox().create_table(conn)
    conn.commit()

    sm = StateMachine(WORKFLOWS, ObjectRepository(), DbApiOutbox(), app_version=APP_VERSION,
                      reject_sink=autonomous_sink(lambda: sqlite3.connect(db)))

    # Normaler Ablauf über UI
    for status, actor, channel in [("Beantragt", "user_017", "ui"), ("Prüfung Data Owner", "owner_03", "ui")]:
        with conn:
            sm.transition("Access Request", "AR-1", status, actor=actor, channel=channel, conn=conn, domain="Finance")

    # Admin versucht, ohne Antrag zu berechtigen -> abgewiesen, aber protokolliert
    try:
        with conn:
            sm.transition("Access Request", "AR-2", "Berechtigung erteilt", actor="admin_01", channel="admin_api", conn=conn)
    except TransitionRejected as e:
        print("abgewiesen:", e)

    for (payload,) in conn.execute("SELECT payload FROM event_outbox ORDER BY seq"):
        e = json.loads(payload)
        print(f"  {e['event_type']:10} {e['from_activity'] or '▶ Start':20} → {e['activity']:20} {e['channel']:9} {e['actor']}")

    files = publish(conn, str(work / "volume_events"))
    print("ausgeliefert nach:", files[0])
    wf = workflow_definition()
    print("Workflow-Export:", wf["release"], sum(len(w["transitions"]) for w in wf["workflows"]), "Übergänge")


if __name__ == "__main__":
    main()
