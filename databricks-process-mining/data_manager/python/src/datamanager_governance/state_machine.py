"""Zentrale Status-Maschine des Data Managers.

Grundsatz: JEDER Statuswechsel – UI, REST-API, Admin-API, Batch, Migration, Automatik – läuft
durch `StateMachine.transition()`. Sie
  1. prüft den Übergang gegen die Workflow-Definition (inkl. erlaubter Kanäle),
  2. ändert den Status über den übergebenen `StatusStore`,
  3. schreibt genau ein ProcessEvent in governance.process_event – in derselben Transaktion,
  4. protokolliert abgewiesene Versuche als `rejected`-Event und wirft TransitionRejected.

Die Anwendung steuert die Transaktion (z. B. SQLAlchemy `with session.begin():` oder Django
`transaction.atomic()`); transition() öffnet selbst keine.

Abgewiesene Versuche: TransitionRejected führt in der Anwendung typischerweise zum Rollback –
das rejected-Event darf dabei NICHT verloren gehen. Deshalb gibt es `reject_sink`: eine Funktion,
die das Event in einer EIGENEN, sofort committeten Transaktion speichert (z. B. eigene Session
bzw. Connection auf dieselbe Tabelle process_event). Ohne reject_sink landet es in der Transaktion des
Aufrufers (nur sinnvoll mit raise_on_reject=False).
"""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Callable, Protocol

from .events import END, START, ProcessEvent
from .event_store import EventStore


@dataclass(frozen=True)
class Rule:
    since_release: str = "2.2"
    note: str = "Standard-Workflow"
    channels: tuple[str, ...] | None = None     # None = alle Kanäle


@dataclass
class Workflow:
    """Erlaubte Übergänge eines Objekttyps. START = Anlage, END = Abschluss."""
    process: str
    transitions: dict[tuple[str, str], Rule] = field(default_factory=dict)
    terminal: dict[str, Rule] = field(default_factory=dict)

    def allow(self, src: str, tgt: str, since_release: str = "2.2", note: str = "Standard-Workflow",
              channels: tuple[str, ...] | None = None) -> "Workflow":
        if (src, tgt) in self.transitions:
            raise ValueError(f"Übergang {src} → {tgt} doppelt definiert")
        self.transitions[(src, tgt)] = Rule(since_release, note, channels)
        return self

    def end(self, *states: str, since_release: str = "2.2") -> "Workflow":
        for s in states:
            self.terminal[s] = Rule(since_release, "Standard-Workflow")
        return self

    def rule(self, src: str, tgt: str) -> Rule | None:
        return self.transitions.get((src, tgt))

    def states(self) -> set[str]:
        return {s for pair in self.transitions for s in pair} - {START}


class StatusStore(Protocol):
    """Lesen/Schreiben des aktuellen Status eines Objekts (Repository der Anwendung)."""
    def get_status(self, process: str, case_id: str, conn) -> str | None: ...
    def set_status(self, process: str, case_id: str, status: str, conn, **attrs) -> None: ...


class TransitionRejected(Exception):
    def __init__(self, event: ProcessEvent):
        super().__init__(event.reason)
        self.event = event


class StateMachine:
    def __init__(self, workflows: list[Workflow], store: StatusStore, events: EventStore,
                 app_version: str, workflow_version: str | None = None,
                 reject_sink: Callable[[ProcessEvent], None] | None = None):
        self.workflows = {w.process: w for w in workflows}
        self.store, self.events, self.reject_sink = store, events, reject_sink
        self.app_version = app_version
        self.workflow_version = workflow_version or app_version

    def allowed_next(self, process: str, case_id: str | None, conn, channel: str = "ui") -> list[dict]:
        """Erlaubte nächste Status für die UI (Vue): nur diese Aktionen anbieten.
        Die Prüfung in transition() bleibt trotzdem maßgeblich (kein Vertrauen in den Client)."""
        current = self.store.get_status(process, case_id, conn) if case_id else None
        src = current or START
        return [{"to": t, "note": r.note}
                for (s, t), r in self.workflows[process].transitions.items()
                if s == src and (r.channels is None or channel in r.channels)]

    def transition(self, process: str, case_id: str, to_status: str, *, actor: str, channel: str, conn,
                   domain: str | None = None, reason: str | None = None, trace_id: str | None = None,
                   object_version: str | None = None, raise_on_reject: bool = True) -> ProcessEvent:
        wf = self.workflows[process]
        current = self.store.get_status(process, case_id, conn)
        src = current or START
        rule = wf.rule(src, to_status)
        allowed = rule is not None and (rule.channels is None or channel in rule.channels)
        if allowed:
            from_activity, why = current, reason          # current ist None bei Anlage
        else:
            from_activity = src                           # bei rejected immer gefüllt (ggf. '▶ Start')
            why = f"Übergang {src} → {to_status} über '{channel}' nicht erlaubt"
        event = ProcessEvent(
            process=process, case_id=case_id, activity=to_status, actor=actor, channel=channel,
            app_version=self.app_version, workflow_version=self.workflow_version,
            event_type="transition" if allowed else "rejected", from_activity=from_activity,
            domain=domain, object_version=object_version, trace_id=trace_id, reason=why,
        )
        if allowed:
            self.store.set_status(process, case_id, to_status, conn, domain=domain)
            self.events.add(event, conn)
        elif self.reject_sink is not None:
            self.reject_sink(event)              # eigene Transaktion: überlebt den Rollback des Aufrufers
        else:
            self.events.add(event, conn)
        if not allowed and raise_on_reject:
            raise TransitionRejected(event)
        return event
