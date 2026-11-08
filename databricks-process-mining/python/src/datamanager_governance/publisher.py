"""Outbox → Databricks: unveröffentlichte Events als JSONL-Datei ablegen.

Ziel ist ein Unity-Catalog-Volume (z. B. /Volumes/main/data_manager_pm/events/), aus dem
12_ingest_events.sql per Auto Loader in die Bronze-Tabelle liest. Für Tests/Entwicklung
geht auch ein lokales Verzeichnis.

    dm-publish-events --db datamanager.sqlite --target ./events_out
    dm-publish-events --dsn ... --target /Volumes/main/data_manager_pm/events   # mit databricks-sdk

Garantie: at-least-once. Doppelte Auslieferung ist unkritisch, weil Databricks nach event_id
dedupliziert. Reihenfolge innerhalb einer Datei = Outbox-Reihenfolge (seq).
"""
from __future__ import annotations

import argparse
import io
import sqlite3
import sys
from datetime import datetime, timezone
from pathlib import Path

from .outbox import DbApiOutbox


def _write(target: str, name: str, data: bytes) -> str:
    if target.startswith("/Volumes/"):
        from databricks.sdk import WorkspaceClient   # optional: pip install datamanager-governance[databricks]
        path = f"{target.rstrip('/')}/{name}"
        WorkspaceClient().files.upload(path, io.BytesIO(data), overwrite=False)
        return path
    p = Path(target)
    p.mkdir(parents=True, exist_ok=True)
    tmp, final = p / f".{name}.tmp", p / name
    tmp.write_bytes(data)
    tmp.rename(final)            # atomar: Auto Loader sieht nie halbe Dateien
    return str(final)


def publish(conn, target: str, outbox: DbApiOutbox | None = None, batch_size: int = 5000) -> list[str]:
    outbox = outbox or DbApiOutbox()
    files = []
    while True:
        rows = outbox.fetch_unpublished(conn, batch_size)
        if not rows:
            return files
        now = datetime.now(timezone.utc)
        name = f"events_{now:%Y%m%dT%H%M%S%f}_{rows[0][0]}-{rows[-1][0]}.jsonl"
        files.append(_write(target, name, ("\n".join(p for _, p in rows) + "\n").encode("utf-8")))
        with conn:
            outbox.mark_published(conn, [s for s, _ in rows], now.isoformat(timespec="seconds"))


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="Outbox-Events als JSONL nach Databricks ausliefern")
    ap.add_argument("--db", required=True, help="SQLite-Datei (für andere DBs publish() mit eigener Verbindung nutzen)")
    ap.add_argument("--target", required=True, help="Verzeichnis oder /Volumes/<catalog>/<schema>/<volume>/<pfad>")
    args = ap.parse_args(argv)
    files = publish(sqlite3.connect(args.db), args.target)
    print(f"{len(files)} Datei(en) geschrieben", *files, sep="\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
