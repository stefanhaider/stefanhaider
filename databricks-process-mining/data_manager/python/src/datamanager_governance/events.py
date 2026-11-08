"""Prozess-Event nach EVENT_STANDARD.md."""
from __future__ import annotations

import json
import uuid
from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone

EVENT_TYPES = {"transition", "rejected"}
CHANNELS = {"ui", "api", "admin_api", "batch", "migration", "system"}
START, END = "▶ Start", "■ Ende"


def _now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


@dataclass(frozen=True)
class ProcessEvent:
    process: str
    case_id: str
    activity: str
    actor: str
    channel: str
    app_version: str
    workflow_version: str
    event_type: str = "transition"
    from_activity: str | None = None
    domain: str | None = None
    object_version: str | None = None
    trace_id: str | None = None
    reason: str | None = None
    event_ts: str = field(default_factory=_now)
    event_id: str = field(default_factory=lambda: str(uuid.uuid4()))

    def __post_init__(self) -> None:
        if self.event_type not in EVENT_TYPES:
            raise ValueError(f"event_type muss einer von {sorted(EVENT_TYPES)} sein, nicht {self.event_type!r}")
        if self.channel not in CHANNELS:
            raise ValueError(f"channel muss einer von {sorted(CHANNELS)} sein, nicht {self.channel!r}")
        for name in ("process", "case_id", "activity", "actor", "app_version", "workflow_version"):
            if not getattr(self, name):
                raise ValueError(f"Pflichtfeld {name} fehlt")
        if self.activity in (START, END):
            raise ValueError("activity darf keine Pseudo-Aktivität sein")
        if self.event_type == "rejected" and not self.from_activity:
            raise ValueError("rejected-Events brauchen from_activity")

    def to_dict(self) -> dict:
        return asdict(self)

    def to_json(self) -> str:
        return json.dumps(self.to_dict(), ensure_ascii=False, separators=(",", ":"))

    @classmethod
    def from_json(cls, payload: str) -> "ProcessEvent":
        return cls(**json.loads(payload))
