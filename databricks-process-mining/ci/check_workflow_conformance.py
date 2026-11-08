#!/usr/bin/env python3
"""Wrapper für Pipelines ohne installiertes Paket. Logik: python/src/datamanager_governance/conformance.py
Mit installiertem Paket (pip install ./python) stattdessen: dm-check-workflow ..."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "python" / "src"))
from datamanager_governance.conformance import main  # noqa: E402

if __name__ == "__main__":
    sys.exit(main())
