import json

from datamanager_governance.conformance import check, classify, main
from datamanager_governance.export import workflow_definition


def _set(d):
    return {(w["process"], t["from"], t["to"], t["since_release"], t["note"]) for w in d["workflows"] for t in w["transitions"]}


def test_export_matches_committed_config(root):
    """governance/workflow_definition.json muss aus dem Code erzeugt sein (dm-export-workflow)."""
    committed = json.loads((root / "governance/workflow_definition.json").read_text(encoding="utf-8"))
    assert _set(workflow_definition()) == _set(committed)


def test_classify_matches_sql_rules(root):
    model = json.loads((root / "governance/governance_model.json").read_text(encoding="utf-8"))
    ar = next(p for p in model["processes"] if p["process"] == "Access Request")
    acts = {a["name"]: a for a in ar["activities"]}
    allowed = {tuple(t) for t in ar["allowed_transitions"]}
    assert classify("Prüfung Data Owner", "Berechtigung erteilt", acts, allowed) == ("Kontrolle umgangen", ["Prüfung Security"])
    assert classify("Prüfung Data Owner", "Beantragt", acts, allowed)[0] == "Rücksprung / Wiederholung"
    assert classify("Beantragt", "Prüfung Data Owner", acts, allowed) == (None, [])


def test_check_findings_on_reference_config(root):
    import datetime as dt
    model = json.loads((root / "governance/governance_model.json").read_text(encoding="utf-8"))
    accepted = json.loads((root / "governance/accepted_deviations.json").read_text(encoding="utf-8"))["accepted"]
    f = check(model, workflow_definition(), accepted, dt.date(2026, 7, 6))
    assert len(f) == 8
    assert sum(x["severity"] == "kritisch" for x in f) == 6
    blocking = [x for x in f if x["severity"] == "kritisch" and (x["accepted"] is None or x["accepted"]["expired"])]
    assert len(blocking) == 6
    assert any(x["check"] == "SOLL_NICHT_UMGESETZT" and x["transition"] == "Review Änderung → Verworfen" for x in f)


def test_cli_exit_code(root):
    args = ["--model", str(root / "governance/governance_model.json"), "--accepted", str(root / "governance/accepted_deviations.json"),
            "--today", "2026-07-06"]
    assert main(args) == 1                                  # 6 offene kritische Befunde
    assert main(args + ["--fail-on", "kritisch", "--accepted", "/nonexistent"]) == 1
