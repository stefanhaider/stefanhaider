#!/usr/bin/env python3
"""
Demo: so nutzt der Data Manager das Paket datamanager_governance (python/).

  * zentrale Status-Maschine (datamanager_governance.workflows) – einziger Weg für Statuswechsel
  * Footprint + Statuswechsel in EINER Transaktion (Tabelle process_event, append-only)
  * abgewiesene Versuche über reject_sink in eigener Transaktion (überleben den Rollback)
  * Databricks liest process_event später per Lakehouse Federation (12_federation_ingest.sql)
  * Export der Status-Maschine für den CI-Check

Die Demo nutzt SQLite. In Produktion: PostgresEventStore + psycopg und die DDL aus
python/sql/postgres/001_process_event.sql.

Ausführen:  pip install ./python   &&   python examples/event_writer_example.py
(ohne Installation: PYTHONPATH=python/src python examples/event_writer_example.py)
"""
import sqlite3
import tempfile
from pathlib import Path

from datamanager_governance.event_store import SqliteEventStore, autonomous_sink
from datamanager_governance.export import workflow_definition
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
    db = Path(tempfile.mkdtemp()) / "datamanager.sqlite"
    conn = sqlite3.connect(db)
    conn.execute("CREATE TABLE objects (process TEXT, case_id TEXT, status TEXT, domain TEXT, PRIMARY KEY (process, case_id))")
    SqliteEventStore().create_table(conn)
    conn.commit()

    sm = StateMachine(WORKFLOWS, ObjectRepository(), SqliteEventStore(), app_version=APP_VERSION,
                      reject_sink=autonomous_sink(lambda: sqlite3.connect(db), SqliteEventStore()))

    for status, actor in [("Beantragt", "user_017"), ("Prüfung Data Owner", "owner_03")]:
        with conn:                                           # Statuswechsel + Footprint: eine Transaktion
            sm.transition("Access Request", "AR-1", status, actor=actor, channel="ui", conn=conn, domain="Finance")
    try:                                                     # Admin ohne Antrag -> abgewiesen, aber protokolliert
        with conn:
            sm.transition("Access Request", "AR-2", "Berechtigung erteilt", actor="admin_01", channel="admin_api", conn=conn)
    except TransitionRejected as e:
        print("abgewiesen:", e)

    for e in SqliteEventStore().fetch_after(conn):
        print(f"  {e['seq']:>2} {e['event_type']:10} {e['from_activity'] or '▶ Start':20} → {e['activity']:20} {e['channel']:9} {e['actor']}")
    wf = workflow_definition()
    print("Workflow-Export:", wf["release"], sum(len(w["transitions"]) for w in wf["workflows"]), "Übergänge")


if __name__ == "__main__":
    main()
