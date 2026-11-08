"""Tests gegen echtes PostgreSQL. Laufen nur mit DM_TEST_PG_DSN, z. B.
    DM_TEST_PG_DSN=postgresql://postgres@127.0.0.1:55432/datamanager pytest -q
Die Datenbank wird verändert (Schema governance wird neu angelegt) – nur Testdatenbanken verwenden!
"""
import os
import uuid
from pathlib import Path

import pytest

psycopg = pytest.importorskip("psycopg")
DSN = os.environ.get("DM_TEST_PG_DSN")
pytestmark = pytest.mark.skipif(not DSN, reason="DM_TEST_PG_DSN nicht gesetzt")

from datamanager_governance.event_store import PostgresEventStore, autonomous_sink  # noqa: E402
from datamanager_governance.events import ProcessEvent  # noqa: E402
from datamanager_governance.state_machine import StateMachine, TransitionRejected  # noqa: E402
from datamanager_governance.workflows import APP_VERSION, WORKFLOWS  # noqa: E402

DDL = (Path(__file__).resolve().parents[1] / "sql/postgres/001_process_event.sql").read_text(encoding="utf-8")


class PgStatusStore:
    def get_status(self, process, case_id, conn):
        r = conn.execute("SELECT status FROM app.objects WHERE process=%s AND case_id=%s", (process, case_id)).fetchone()
        return r[0] if r else None

    def set_status(self, process, case_id, status, conn, **attrs):
        conn.execute("INSERT INTO app.objects VALUES (%s,%s,%s,%s) ON CONFLICT (process, case_id) DO UPDATE SET status=EXCLUDED.status",
                     (process, case_id, status, attrs.get("domain")))


@pytest.fixture
def pg():
    with psycopg.connect(DSN, autocommit=True) as c:
        c.execute("DROP SCHEMA IF EXISTS governance CASCADE; DROP SCHEMA IF EXISTS app CASCADE")
        c.execute(DDL)
        c.execute(DDL)   # idempotent
        c.execute("CREATE SCHEMA app; CREATE TABLE app.objects (process TEXT, case_id TEXT, status TEXT, domain TEXT, PRIMARY KEY (process, case_id))")
    conn = psycopg.connect(DSN)
    yield conn
    conn.close()


@pytest.fixture
def sm():
    return StateMachine(WORKFLOWS, PgStatusStore(), PostgresEventStore(), app_version=APP_VERSION,
                        reject_sink=autonomous_sink(lambda: psycopg.connect(DSN), PostgresEventStore()))


def rows(conn):
    return PostgresEventStore().fetch_after(conn)


def test_transitions_are_stored_with_columns(sm, pg):
    with pg.transaction():
        sm.transition("Access Request", "AR-1", "Beantragt", actor="user_017", channel="ui", conn=pg, domain="Finance")
        sm.transition("Access Request", "AR-1", "Prüfung Data Owner", actor="owner_03", channel="ui", conn=pg)
    r = rows(pg)
    assert [(x["from_activity"], x["activity"], x["event_type"]) for x in r] == \
           [(None, "Beantragt", "transition"), ("Beantragt", "Prüfung Data Owner", "transition")]
    assert isinstance(r[0]["event_id"], uuid.UUID) and r[0]["event_ts"].tzinfo is not None


def test_rejected_survives_rollback_even_after_prior_write(sm, pg):
    with pg.transaction():
        sm.transition("Data Product", "DP-1", "Angelegt", actor="user_042", channel="ui", conn=pg)
    with pytest.raises(TransitionRejected):
        with pg.transaction():                                   # wird zurückgerollt
            pg.execute("UPDATE app.objects SET domain = 'X' WHERE case_id = 'DP-1'")   # vorheriger Write
            sm.transition("Data Product", "DP-1", "Veröffentlicht", actor="user_042", channel="ui", conn=pg)
    r = rows(pg)
    assert r[-1]["event_type"] == "rejected" and r[-1]["from_activity"] == "Angelegt"
    assert pg.execute("SELECT status, domain FROM app.objects WHERE case_id='DP-1'").fetchone() == ("Angelegt", None)


def test_append_only_trigger(sm, pg):
    with pg.transaction():
        sm.transition("Access Request", "AR-2", "Beantragt", actor="u", channel="ui", conn=pg)
    for stmt in ["UPDATE governance.process_event SET actor = 'x'", "DELETE FROM governance.process_event",
                 "TRUNCATE governance.process_event"]:
        with pytest.raises(psycopg.errors.InsufficientPrivilege):
            with pg.transaction():
                pg.execute(stmt)


def _event(case_id):
    return ProcessEvent(process="Access Request", case_id=case_id, activity="Beantragt", actor="u", channel="ui",
                        app_version="2.5", workflow_version="2.5")


def test_roles_writer_insert_only_reader_select_only(pg):
    store = PostgresEventStore()
    with pg.transaction():                                   # App-Rolle: INSERT erlaubt
        pg.execute("SET LOCAL ROLE dm_event_writer")
        store.add(_event("AR-3"), pg)
    with pytest.raises(psycopg.errors.InsufficientPrivilege):
        with pg.transaction():                               # App-Rolle: kein SELECT
            pg.execute("SET LOCAL ROLE dm_event_writer")
            pg.execute("SELECT count(*) FROM governance.process_event")
    with pg.transaction():                                   # Databricks-Rolle: SELECT erlaubt
        pg.execute("SET LOCAL ROLE dm_event_reader")
        assert pg.execute("SELECT count(*) FROM governance.process_event").fetchone()[0] == 1
    with pytest.raises(psycopg.errors.InsufficientPrivilege):
        with pg.transaction():                               # Databricks-Rolle: kein INSERT
            pg.execute("SET LOCAL ROLE dm_event_reader")
            store.add(_event("AR-4"), pg)


def test_watermark_overlap_catches_late_commit(sm):
    """Warum 12_federation_ingest.sql mit Überlappungsfenster auf recorded_at kopiert statt 'seq > max(seq)':
    T1 bekommt seq 1, committet aber NACH T2 (seq 2). Eine Kopie zwischen den Commits sieht nur seq 2."""
    with psycopg.connect(DSN, autocommit=True) as c:
        c.execute("DROP SCHEMA IF EXISTS governance CASCADE; DROP SCHEMA IF EXISTS app CASCADE")
        c.execute(DDL)
        c.execute("CREATE SCHEMA app; CREATE TABLE app.objects (process TEXT, case_id TEXT, status TEXT, domain TEXT, PRIMARY KEY (process, case_id))")
    t1, t2, reader = psycopg.connect(DSN), psycopg.connect(DSN), psycopg.connect(DSN, autocommit=True)
    sm.transition("Access Request", "AR-A", "Beantragt", actor="u1", channel="ui", conn=t1)   # seq 1, offen
    sm.transition("Access Request", "AR-B", "Beantragt", actor="u2", channel="ui", conn=t2)   # seq 2
    t2.commit()

    bronze = {}                                      # Delta-Tabelle in Databricks (key = event_id)
    def copy_naive(last_seq):
        new = reader.execute("SELECT seq, event_id FROM governance.process_event WHERE seq > %s", (last_seq,)).fetchall()
        bronze.update({e: s for s, e in new})
        return max([last_seq] + [s for s, _ in new])
    def copy_overlap():                              # Logik aus 12_federation_ingest.sql
        wm = reader.execute("SELECT coalesce(max(recorded_at), '-infinity') FROM governance.process_event "
                            "WHERE event_id = ANY(%s)", (list(bronze) or [uuid.uuid4()],)).fetchone()[0]
        new = reader.execute("SELECT seq, event_id FROM governance.process_event "
                             "WHERE recorded_at >= %s - interval '15 minutes'", (wm,)).fetchall()
        for s, e in new:
            bronze.setdefault(e, s)                  # MERGE ... WHEN NOT MATCHED THEN INSERT

    last = copy_naive(0)                             # sieht nur seq 2
    t1.commit()                                      # seq 1 wird jetzt sichtbar
    copy_naive(last)
    assert sorted(bronze.values()) == [2]            # naive Kopie hat seq 1 verloren
    copy_overlap()
    assert sorted(bronze.values()) == [1, 2]         # Überlappungsfenster findet sie
    for c in (t1, t2, reader):
        c.close()
