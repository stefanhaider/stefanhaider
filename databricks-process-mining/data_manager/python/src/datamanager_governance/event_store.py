"""Speicherung der Prozess-Footprints in der Datenbank des Data Managers.

`StateMachine.transition()` schreibt jedes Event über einen EventStore in die Tabelle
`governance.process_event` – in DERSELBEN Transaktion wie den Statuswechsel. Die Tabelle ist
append-only und der dauerhafte Audit-Trail; Databricks liest sie über Lakehouse Federation
(12_federation_ingest.sql). Ein eigener Versand-Job ist nicht nötig.

PostgreSQL-DDL inkl. Append-only-Trigger und Rollen: python/sql/postgres/001_process_event.sql

Verwendung:
    store = PostgresEventStore()                 # psycopg 3, paramstyle %s
    store.add(event, conn)                       # conn = Verbindung/Session der laufenden Transaktion

SQLAlchemy (Session der Anwendung):
    class SqlAlchemyEventStore(PostgresEventStore):
        def add(self, event, session):
            session.execute(text(self.insert_sql_named), event.to_dict())

Django: `with transaction.atomic(): obj.save(); store.add(event, connection)` (django.db.connection).
"""
from __future__ import annotations

from typing import Protocol

from .events import ProcessEvent

COLUMNS = ("event_id", "event_type", "process", "case_id", "object_version", "domain", "from_activity",
           "activity", "actor", "channel", "app_version", "workflow_version", "trace_id", "reason", "event_ts")

SQLITE_DDL = """
CREATE TABLE IF NOT EXISTS process_event (
    seq INTEGER PRIMARY KEY AUTOINCREMENT,
    event_id TEXT NOT NULL UNIQUE, event_type TEXT NOT NULL, process TEXT NOT NULL, case_id TEXT NOT NULL,
    object_version TEXT, domain TEXT, from_activity TEXT, activity TEXT NOT NULL, actor TEXT NOT NULL,
    channel TEXT NOT NULL, app_version TEXT NOT NULL, workflow_version TEXT NOT NULL, trace_id TEXT,
    reason TEXT, event_ts TEXT NOT NULL, recorded_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);
CREATE TRIGGER IF NOT EXISTS process_event_no_update BEFORE UPDATE ON process_event
BEGIN SELECT RAISE(ABORT, 'process_event ist append-only'); END;
CREATE TRIGGER IF NOT EXISTS process_event_no_delete BEFORE DELETE ON process_event
BEGIN SELECT RAISE(ABORT, 'process_event ist append-only'); END;
"""


class EventStore(Protocol):
    def add(self, event: ProcessEvent, conn) -> None: ...


class DbApiEventStore:
    """EventStore für DB-API-2.0-Verbindungen. table/paramstyle je Datenbank."""

    def __init__(self, table: str, paramstyle: str):
        self.table = table
        ph = ", ".join([paramstyle] * len(COLUMNS))
        self.insert_sql = f"INSERT INTO {table} ({', '.join(COLUMNS)}) VALUES ({ph})"
        self.insert_sql_named = f"INSERT INTO {table} ({', '.join(COLUMNS)}) VALUES ({', '.join(':' + c for c in COLUMNS)})"

    def add(self, event: ProcessEvent, conn) -> None:
        d = event.to_dict()
        conn.execute(self.insert_sql, tuple(d[c] for c in COLUMNS))

    def fetch_after(self, conn, seq: int = 0, limit: int = 1000) -> list[dict]:
        """Nur für Tests/Diagnose (die App-Rolle braucht kein SELECT)."""
        cur = conn.execute(f"SELECT seq, {', '.join(COLUMNS)} FROM {self.table} WHERE seq > {int(seq)} "
                           f"ORDER BY seq LIMIT {int(limit)}")
        return [dict(zip(("seq",) + COLUMNS, r)) for r in cur.fetchall()]


class PostgresEventStore(DbApiEventStore):
    def __init__(self, table: str = "governance.process_event"):
        super().__init__(table, "%s")


class SqliteEventStore(DbApiEventStore):
    """Für Tests und lokale Entwicklung."""

    def __init__(self, table: str = "process_event"):
        super().__init__(table, "?")

    def create_table(self, conn) -> None:
        conn.executescript(SQLITE_DDL)


def autonomous_sink(connect, store: EventStore):
    """reject_sink, der jedes rejected-Event über eine EIGENE Verbindung sofort committet –
    es überlebt so den Rollback, den TransitionRejected in der Anwendung auslöst.

        sm = StateMachine(..., reject_sink=autonomous_sink(lambda: psycopg.connect(DSN), PostgresEventStore()))
    SQLAlchemy:  def sink(e): with engine.begin() as c: SqlAlchemyEventStore().add(e, c)

    Hinweis SQLite: nur ein Schreiber gleichzeitig – hat der Aufrufer in seiner offenen Transaktion
    bereits geschrieben, blockiert die zweite Verbindung. PostgreSQL: kein Problem (Zeilensperren).
    """
    def sink(event: ProcessEvent) -> None:
        c = connect()
        try:
            with c:              # sqlite3: commit; psycopg 3: commit + close
                store.add(event, c)
        finally:
            c.close()
    return sink
