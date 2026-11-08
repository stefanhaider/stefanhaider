import sqlite3
from pathlib import Path

import pytest

from datamanager_governance.event_store import SqliteEventStore, autonomous_sink
from datamanager_governance.state_machine import StateMachine
from datamanager_governance.workflows import APP_VERSION, WORKFLOWS

ROOT = Path(__file__).resolve().parents[2]      # data_manager/


class SqliteStore:
    """Minimaler StatusStore für Tests (in der Anwendung: Repository/ORM)."""
    def get_status(self, process, case_id, conn):
        row = conn.execute("SELECT status FROM objects WHERE process = ? AND case_id = ?", (process, case_id)).fetchone()
        return row[0] if row else None

    def set_status(self, process, case_id, status, conn, **attrs):
        conn.execute("INSERT INTO objects (process, case_id, status, domain) VALUES (?, ?, ?, ?) "
                     "ON CONFLICT(process, case_id) DO UPDATE SET status = excluded.status",
                     (process, case_id, status, attrs.get("domain")))


@pytest.fixture
def db_path(tmp_path):
    return tmp_path / "datamanager.sqlite"


@pytest.fixture
def conn(db_path):
    c = sqlite3.connect(db_path)
    c.execute("CREATE TABLE objects (process TEXT, case_id TEXT, status TEXT, domain TEXT, PRIMARY KEY (process, case_id))")
    SqliteEventStore().create_table(c)
    c.commit()
    yield c
    c.close()


@pytest.fixture
def sm(db_path, conn):
    return StateMachine(WORKFLOWS, SqliteStore(), SqliteEventStore(), app_version=APP_VERSION,
                        reject_sink=autonomous_sink(lambda: sqlite3.connect(db_path), SqliteEventStore()))


@pytest.fixture
def root():
    return ROOT
