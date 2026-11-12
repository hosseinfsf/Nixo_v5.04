"""Atomic file protocol shared by Nixo Control Center and the MT5 bridge."""
from __future__ import annotations

import json
import os
import tempfile
import time
from pathlib import Path
from typing import Any


def load_control(path: Path) -> dict[str, Any] | None:
    """Return None when no controller has been installed; reject malformed files."""
    try:
        with path.open("r", encoding="utf-8") as control_file:
            data = json.load(control_file)
    except FileNotFoundError:
        return None
    if not isinstance(data, dict):
        raise ValueError("control.json must contain a JSON object")
    return data


def control_enabled(control: dict[str, Any] | None) -> bool:
    if control is None:
        return False
    return (
        control.get("system_enabled") is True
        and control.get("accept_new_signals") is True
        and control.get("demo_only") is True
        and control.get("trading_mode") == "EXTERNAL"
    )


def write_control(path: Path, enabled: bool) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    data = {
        "protocol_version": 1,
        "system_enabled": enabled,
        "trading_mode": "EXTERNAL",
        "accept_new_signals": enabled,
        "demo_only": True,
        "updated_at": int(time.time()),
    }
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{path.name}.", suffix=".tmp", dir=path.parent
    )
    temporary_path = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8", newline="\n") as control_file:
            json.dump(data, control_file, separators=(",", ":"))
            control_file.write("\n")
            control_file.flush()
            os.fsync(control_file.fileno())
        os.replace(temporary_path, path)
    except BaseException:
        temporary_path.unlink(missing_ok=True)
        raise
