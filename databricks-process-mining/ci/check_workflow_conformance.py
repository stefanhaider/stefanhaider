#!/usr/bin/env python3
"""
CI-Check: Status-Maschine des Data Managers gegen den Soll-Prozess der Governance.

Vergleicht vor jedem Release (ohne Event-Daten!)
  * config/governance_model.json     – Soll-Prozess (gehört der Governance)
  * config/workflow_definition.json  – Export der Status-Maschine (gehört dem Data Manager)
und meldet:
  * SYSTEM_ERLAUBT_MEHR    – das System erlaubt einen Übergang, den das Soll nicht vorsieht
                             (umgeht er einen Kontrollschritt: kritisch, sonst mittel)
  * SOLL_NICHT_UMGESETZT   – das Soll verlangt/erlaubt einen Übergang, das System bietet ihn nicht an (hoch)
  * UNBEKANNTE_AKTIVITAET  – das System kennt einen Status, den das Soll nicht kennt (mittel)

Genehmigte Ausnahmen stehen in ci/accepted_deviations.json (mit Begründung, Genehmiger, Ablaufdatum).
Exit-Code 1, wenn ein Befund mit Schwere >= --fail-on nicht genehmigt ist (Standard: kritisch).

Die Klassifizierung entspricht exakt v_transition_classes in 03_views.sql.

Aufruf:
  python ci/check_workflow_conformance.py \
      --model config/governance_model.json \
      --workflow config/workflow_definition.json \
      --accepted ci/accepted_deviations.json \
      [--fail-on kritisch|hoch|mittel] [--json report.json] [--today 2026-07-06]

Nur Python-Standardbibliothek, keine Abhängigkeiten.
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import sys
from pathlib import Path

SEVERITY_RANK = {"kritisch": 1, "hoch": 2, "mittel": 3}


def classify(src: str, tgt: str, acts: dict, allowed: set) -> tuple[str | None, list[str]]:
    """Gleiche Regeln wie v_transition_classes: (finding_type, übersprungene Kontrollen)."""
    if (src, tgt) in allowed:
        return None, []
    ms, mt = acts.get(src), acts.get(tgt)
    if ms is None or mt is None:
        return "Zusätzliche Aktivität", []
    if tgt == "■ Ende":
        return "Kein gültiger Abschluss", []
    if mt["is_terminal"]:
        return "Abbruch an unzulässiger Stelle", []
    if mt["step_order"] <= ms["step_order"]:
        return "Rücksprung / Wiederholung", []
    skipped = [a["name"] for a in sorted(acts.values(), key=lambda a: a["step_order"])
               if a["is_control"] and ms["step_order"] < a["step_order"] < mt["step_order"]]
    if skipped:
        return "Kontrolle umgangen", skipped
    if mt["step_order"] > ms["step_order"] + 1:
        return "Schritt übersprungen", []
    return "Unzulässiger Übergang", []


def check(model: dict, workflow: dict, accepted: list[dict], today: dt.date) -> list[dict]:
    wf_by_process = {w["process"]: w for w in workflow["workflows"]}
    findings = []
    for proc in model["processes"]:
        p = proc["process"]
        acts = {a["name"]: a for a in proc["activities"]}
        soll = {tuple(t) for t in proc["allowed_transitions"]}
        wf = wf_by_process.get(p)
        if wf is None:
            findings.append({"process": p, "check": "PROZESS_FEHLT", "transition": None, "severity": "hoch",
                             "detail": "Prozess ist im Soll-Modell, aber nicht in der Workflow-Definition."})
            continue
        system = {(t["from"], t["to"]): t for t in wf["transitions"]}

        for (src, tgt), t in sorted(system.items()):
            if (src, tgt) in soll:
                continue
            ftype, skipped = classify(src, tgt, acts, soll)
            for name in (src, tgt):
                if name not in acts:
                    findings.append({"process": p, "check": "UNBEKANNTE_AKTIVITAET", "transition": f"{src} → {tgt}",
                                     "severity": "mittel", "detail": f"Status '{name}' ist nicht im Soll-Modell."})
            sev = "kritisch" if ftype == "Kontrolle umgangen" else "mittel"
            detail = f"{ftype}" + (f": {', '.join(skipped)}" if skipped else "")
            findings.append({"process": p, "check": "SYSTEM_ERLAUBT_MEHR", "transition": f"{src} → {tgt}",
                             "severity": sev, "detail": detail,
                             "since_release": t.get("since_release"), "note": t.get("note")})

        for src, tgt in sorted(soll - set(system)):
            findings.append({"process": p, "check": "SOLL_NICHT_UMGESETZT", "transition": f"{src} → {tgt}",
                             "severity": "hoch", "detail": "Im Soll-Prozess vorgesehen, im Workflow nicht angeboten."})

    # Genehmigte Ausnahmen anwenden (nur gültige, nicht abgelaufene)
    for f in findings:
        f["accepted"] = None
        for a in accepted:
            if a["process"] == f["process"] and a["transition"] == f["transition"] and a["check"] == f["check"]:
                expired = a.get("expires") and dt.date.fromisoformat(a["expires"]) < today
                f["accepted"] = {**a, "expired": bool(expired)}
    return findings


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--model", default="config/governance_model.json")
    ap.add_argument("--workflow", default="config/workflow_definition.json")
    ap.add_argument("--accepted", default="ci/accepted_deviations.json")
    ap.add_argument("--fail-on", default="kritisch", choices=list(SEVERITY_RANK))
    ap.add_argument("--json", help="Bericht zusätzlich als JSON schreiben")
    ap.add_argument("--today", help="Stichtag für Ablaufdaten (ISO), Standard: heute")
    args = ap.parse_args()

    model = json.loads(Path(args.model).read_text(encoding="utf-8"))
    workflow = json.loads(Path(args.workflow).read_text(encoding="utf-8"))
    accepted_path = Path(args.accepted)
    accepted = json.loads(accepted_path.read_text(encoding="utf-8"))["accepted"] if accepted_path.exists() else []
    today = dt.date.fromisoformat(args.today) if args.today else dt.date.today()

    findings = check(model, workflow, accepted, today)
    findings.sort(key=lambda f: (SEVERITY_RANK[f["severity"]], f["process"], f["transition"] or ""))
    limit = SEVERITY_RANK[args.fail_on]
    blocking = [f for f in findings if SEVERITY_RANK[f["severity"]] <= limit
                and (f["accepted"] is None or f["accepted"]["expired"])]

    print(f"Workflow-Konformität: {workflow.get('application')} Release {workflow.get('release')} "
          f"gegen Soll-Modell {model.get('model_version')}\n")
    for f in findings:
        if f["accepted"] and not f["accepted"]["expired"]:
            state = f"GENEHMIGT bis {f['accepted'].get('expires')} ({f['accepted'].get('approved_by')})"
        elif f["accepted"]:
            state = "GENEHMIGUNG ABGELAUFEN"
        else:
            state = "OFFEN"
        extra = f" [seit {f['since_release']}: {f['note']}]" if f.get("since_release") else ""
        print(f"  {f['severity']:8} {f['check']:22} {f['process']:15} {f['transition'] or '-'}")
        print(f"           {f['detail']}{extra}  -> {state}")
    print(f"\n{len(findings)} Befunde, davon {len(blocking)} blockierend (Schwere >= {args.fail_on}, nicht genehmigt).")

    if args.json:
        Path(args.json).write_text(json.dumps({"findings": findings, "blocking": len(blocking)},
                                              ensure_ascii=False, indent=2), encoding="utf-8")
    return 1 if blocking else 0


if __name__ == "__main__":
    sys.exit(main())
