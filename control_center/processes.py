"""Start, stop, and monitor the helper processes the Control Center owns.

The bridges are ordinary Python scripts. They are never duplicated: before a
launch, the caller checks the heartbeat the bridge publishes.
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path

from .paths import AI_BRIDGE_DIR, BRIDGE_DIR, nixo_common_dir

BRIDGE_SCRIPT = BRIDGE_DIR / "signal_bridge.py"
AI_BRIDGE_SCRIPT = AI_BRIDGE_DIR / "nixo_ai_bridge.py"
TELEGRAM_SESSION = BRIDGE_DIR / "nixo_telegram.session"
STOP_GRACE_SECONDS = 6.0


@dataclass
class ProcessState:
    running: bool
    detail: str


def read_status(name: str) -> dict | None:
    """Read a heartbeat JSON published by a helper process."""
    try:
        raw = (nixo_common_dir() / name).read_text(encoding="utf-8")
        value = json.loads(raw)
    except (OSError, ValueError):
        return None
    return value if isinstance(value, dict) else None


def heartbeat_age(status: dict | None, key: str) -> float | None:
    if not status:
        return None
    try:
        return time.time() - int(status[key])
    except (KeyError, TypeError, ValueError):
        return None


def external_instance_running(filename: str, key: str, max_age: int = 15) -> bool:
    """True when a bridge started elsewhere is still publishing a heartbeat."""
    age = heartbeat_age(read_status(filename), key)
    return age is not None and 0 <= age <= max_age


class ProcessManager:
    """Owns at most one instance of each helper script."""

    def __init__(self) -> None:
        self._children: dict[str, subprocess.Popen] = {}

    def _window_flags(self, hidden: bool) -> int:
        if os.name != "nt" or not hidden:
            return 0
        return subprocess.CREATE_NO_WINDOW

    def start_bridge(self, hidden: bool = True) -> ProcessState:
        if external_instance_running("bridge_status.json", "last_heartbeat", 12):
            return ProcessState(False, "A Signal Bridge is already running.")
        child = self._children.get("bridge")
        if child is not None and child.poll() is None:
            return ProcessState(False, "A Signal Bridge is already running.")
        if not BRIDGE_SCRIPT.is_file():
            return ProcessState(False, f"Missing script: {BRIDGE_SCRIPT}")
        # First Telegram login needs a visible console for the phone/code prompt.
        needs_console = not TELEGRAM_SESSION.exists()
        return self._spawn("bridge", BRIDGE_SCRIPT, BRIDGE_DIR, hidden and not needs_console)

    def start_ai_bridge(self, hidden: bool = True) -> ProcessState:
        env_file = AI_BRIDGE_DIR / ".env.local"
        if not env_file.is_file():
            return ProcessState(False, "ai_bridge/.env.local is missing. Run the setup step first.")
        child = self._children.get("ai")
        if child is not None and child.poll() is None:
            return ProcessState(False, "The AI bridge is already running.")
        if not AI_BRIDGE_SCRIPT.is_file():
            return ProcessState(False, f"Missing script: {AI_BRIDGE_SCRIPT}")
        return self._spawn("ai", AI_BRIDGE_SCRIPT, AI_BRIDGE_DIR, hidden)

    def _spawn(self, key: str, script: Path, cwd: Path, hidden: bool) -> ProcessState:
        try:
            child = subprocess.Popen(
                [sys.executable, str(script)],
                cwd=str(cwd),
                creationflags=self._window_flags(hidden),
            )
        except (OSError, subprocess.SubprocessError) as exc:
            return ProcessState(False, f"Could not start {script.name}: {exc}")
        self._children[key] = child
        return ProcessState(True, f"Started {script.name} (pid {child.pid}).")

    def stop(self, key: str) -> ProcessState:
        child = self._children.get(key)
        if child is None or child.poll() is not None:
            self._children.pop(key, None)
            return ProcessState(False, "Nothing to stop.")
        child.terminate()
        try:
            child.wait(timeout=STOP_GRACE_SECONDS)
        except subprocess.TimeoutExpired:
            child.kill()
            child.wait(timeout=STOP_GRACE_SECONDS)
        self._children.pop(key, None)
        return ProcessState(True, "Stopped.")

    def stop_all(self) -> None:
        for key in list(self._children):
            self.stop(key)

    def is_running(self, key: str) -> bool:
        child = self._children.get(key)
        return child is not None and child.poll() is None
