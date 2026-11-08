"""Outbox-Pattern: Event in derselben DB-Transaktion wie die Statusänderung speichern.

Die StateMachine ruft `outbox.add(event, conn)` innerhalb der Transaktion der Anwendung auf.
Ein separater Publisher (publisher.py) liest unveröffentlichte Events und liefert sie aus.

Für SQLAlchemy (Beispiel):

    class SqlAlchemyOutbox:
        def add(self, event, conn):          # conn = Session oder Connection der laufenden Transaktion
            conn.execute(text("INSERT INTO event_outbox (event_id, created_at, payload) "
                              "VALUES (:id, :ts, :p)"), {"id": event.event_id, "ts": event.event_ts,
                                                         "p": event.to_json()})

Für Django:  OutboxEvent.objects.create(event_id=..., payload=...) innerhalb von
`transaction.atomic()` – im selben Block wie das Speichern des Objekts.
"""
from __future__ import annotations

from typing import Iterable, Protocol

from .events import ProcessEvent

DDL = """
CREATE TABLE IF NOT EXISTS event_outbox (
    seq          INTEGER PRIMARY KEY AUTOINCREMENT,   -- Postgres: BIGSERIAL
    event_id     TEXT NOT NULL UNIQUE,
    created_at   TEXT NOT NULL,
    payload      TEXT NOT NULL,
    published_at TEXT
)
"""


class Outbox(Protocol):
    def add(self, event: ProcessEvent, conn) -> None: ...


class DbApiOutbox:
    """Outbox für DB-API-2.0-Verbindungen (sqlite3, psycopg, ...). paramstyle '?' (sqlite) oder '%s'."""

    def __init__(self, paramstyle: str = "?"):
        self.p = paramstyle

    def create_table(self, conn) -> None:
        conn.execute(DDL)

    def add(self, event: ProcessEvent, conn) -> None:
        p = self.p
        conn.execute(f"INSERT INTO event_outbox (event_id, created_at, payload) VALUES ({p}, {p}, {p})",
                     (event.event_id, event.event_ts, event.to_json()))

    def fetch_unpublished(self, conn, limit: int = 1000) -> list[tuple[int, str]]:
        cur = conn.execute(f"SELECT seq, payload FROM event_outbox WHERE published_at IS NULL "
                           f"ORDER BY seq LIMIT {int(limit)}")
        return list(cur.fetchall())

    def mark_published(self, conn, seqs: Iterable[int], published_at: str) -> None:
        p = self.p
        conn.executemany(f"UPDATE event_outbox SET published_at = {p} WHERE seq = {p}",
                         [(published_at, s) for s in seqs])


def autonomous_sink(connect, outbox: DbApiOutbox | None = None):
    """reject_sink, der jedes rejected-Event über eine eigene Verbindung sofort committet.

        sm = StateMachine(..., reject_sink=autonomous_sink(lambda: sqlite3.connect("dm.sqlite")))
    SQLAlchemy:  def sink(e): with engine.begin() as c: SqlAlchemyOutbox().add(e, c)

    Hinweis SQLite: nur ein Schreiber gleichzeitig – hat der Aufrufer in seiner offenen Transaktion
    bereits geschrieben, blockiert die zweite Verbindung. Mit Postgres/MySQL (Zeilensperren) kein Problem.
    """
    outbox = outbox or DbApiOutbox()

    def sink(event: ProcessEvent) -> None:
        c = connect()
        try:
            with c:
                outbox.add(event, c)
        finally:
            c.close()
    return sink
