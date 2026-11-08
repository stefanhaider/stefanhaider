import sqlite3

import pytest

from datamanager_governance.events import ProcessEvent
from datamanager_governance.event_store import SqliteEventStore
from datamanager_governance.state_machine import TransitionRejected, Workflow


def stored_events(conn):
    return SqliteEventStore().fetch_after(conn)


def test_happy_path_writes_one_event_per_transition(sm, conn):
    for status, actor in [("Beantragt", "user_017"), ("Prüfung Data Owner", "owner_03"),
                          ("Prüfung Security", "security_01"), ("Berechtigung erteilt", "system")]:
        with conn:
            sm.transition("Access Request", "AR-1", status, actor=actor,
                          channel="system" if actor == "system" else "ui", conn=conn, domain="Finance")
    ev = stored_events(conn)
    assert [e["activity"] for e in ev] == ["Beantragt", "Prüfung Data Owner", "Prüfung Security", "Berechtigung erteilt"]
    assert ev[0]["from_activity"] is None and ev[1]["from_activity"] == "Beantragt"
    assert {e["event_type"] for e in ev} == {"transition"}
    assert all(e["app_version"] == "2.5" and e["event_id"] for e in ev)


def test_rejected_attempt_survives_rollback_of_caller(sm, conn):
    with conn:
        sm.transition("Data Product", "DP-1", "Angelegt", actor="user_042", channel="ui", conn=conn)
    with pytest.raises(TransitionRejected) as exc:
        with conn:                       # Anwendung: Transaktion wird wegen der Exception zurückgerollt
            # (SQLite erlaubt nur einen Schreiber; mit Postgres darf der Aufrufer hier bereits geschrieben haben)
            sm.transition("Data Product", "DP-1", "Veröffentlicht", actor="user_042", channel="ui", conn=conn)
    assert exc.value.event.event_type == "rejected"
    ev = stored_events(conn)
    assert ev[-1]["event_type"] == "rejected" and ev[-1]["from_activity"] == "Angelegt"   # Event ist da (eigene Transaktion)
    assert sm.store.get_status("Data Product", "DP-1", conn) == "Angelegt"                 # Status unverändert


def test_rejected_creation_has_start_as_from_activity(sm, conn):
    ev = sm.transition("Access Request", "AR-9", "Berechtigung erteilt", actor="admin_01", channel="admin_api",
                       conn=conn, raise_on_reject=False)
    assert ev.event_type == "rejected" and ev.from_activity == "▶ Start"


def test_channel_restriction():
    wf = Workflow("X").allow("▶ Start", "A").allow("A", "B", channels=("batch",))
    assert wf.rule("A", "B").channels == ("batch",)


def test_event_validation():
    with pytest.raises(ValueError):
        ProcessEvent(process="P", case_id="1", activity="A", actor="u", channel="fax", app_version="1", workflow_version="1")
    with pytest.raises(ValueError):
        ProcessEvent(process="P", case_id="1", activity="A", actor="u", channel="ui", app_version="1",
                     workflow_version="1", event_type="rejected")


def test_sqlite_table_is_append_only(sm, conn):
    with conn:
        sm.transition("Access Request", "AR-5", "Beantragt", actor="user_1", channel="ui", conn=conn)
    with pytest.raises(sqlite3.DatabaseError):
        conn.execute("UPDATE process_event SET actor = 'x'")
    with pytest.raises(sqlite3.DatabaseError):
        conn.execute("DELETE FROM process_event")
