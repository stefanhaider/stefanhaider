"""Prozess- und Governance-Monitoring für den Data Manager.

Module:
    events        – ProcessEvent nach EVENT_STANDARD.md
    state_machine – Workflow-Definitionen und StateMachine.transition() (einziger Weg für Statuswechsel)
    event_store   – Speicherung in governance.process_event (PostgreSQL; SQLite für Tests)
    workflows     – die Status-Maschinen des Data Managers (Single Source of Truth im Code)
    export        – Export von workflow_definition.json (CLI: dm-export-workflow)
    conformance   – Prüfung Status-Maschine vs. Soll-Prozess (CLI: dm-check-workflow)

Transport nach Databricks: keiner im Paket nötig – Databricks liest governance.process_event
über Lakehouse Federation (12_federation_ingest.sql).
"""
__version__ = "0.1.0"
