"""Prozess- und Governance-Monitoring für den Data Manager.

Module:
    events        – ProcessEvent nach EVENT_STANDARD.md
    state_machine – Workflow-Definitionen und StateMachine.transition() (einziger Weg für Statuswechsel)
    outbox        – Outbox-Schnittstelle + DB-API-Implementierung (SQLite, Postgres, ...)
    workflows     – die Status-Maschinen des Data Managers (Single Source of Truth im Code)
    export        – Export von workflow_definition.json (CLI: dm-export-workflow)
    conformance   – Prüfung Status-Maschine vs. Soll-Prozess (CLI: dm-check-workflow)
    publisher     – Outbox → JSONL-Dateien (lokal oder Unity-Catalog-Volume) (CLI: dm-publish-events)
"""
__version__ = "0.1.0"
