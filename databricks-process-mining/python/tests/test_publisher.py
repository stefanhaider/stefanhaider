import json

from datamanager_governance.publisher import publish


def test_publish_writes_jsonl_and_marks_published(sm, conn, tmp_path):
    with conn:
        sm.transition("Data Contract", "DC-1", "Entwurf erstellt", actor="user_001", channel="ui", conn=conn)
        sm.transition("Data Contract", "DC-1", "Schema validiert", actor="system", channel="system", conn=conn)
    files = publish(conn, str(tmp_path))
    assert len(files) == 1
    lines = [json.loads(l) for l in open(files[0], encoding="utf-8")]
    assert [l["activity"] for l in lines] == ["Entwurf erstellt", "Schema validiert"]
    assert publish(conn, str(tmp_path)) == []              # nichts mehr offen
    assert not list(tmp_path.glob(".*.tmp"))
