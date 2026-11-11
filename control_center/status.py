"""Read-only snapshot of every moving part the Control Center displays."""
from __future__ import annotations

import json
import sys
import time
from dataclasses import dataclass, field

from . import paths
from .processes import read_status
from .setup_state import CheckItem, enabled_telegram_sources, is_ready, readiness

EA_HEARTBEAT_MAX_AGE = 15
BRIDGE_HEARTBEAT_MAX_AGE = 12


@dataclass
class Snapshot:
    enabled: bool = False
    control_valid: bool = False
    ea_online: bool = False
    ea_demo: bool = False
    ea_running: bool = False
    ea_version: str = ""
    ea_mode: str = "Unknown"
    ea_live: bool = False
    ea_signal_lab: bool = False
    ea_symbol: str = ""
    bridge_running: bool = False
    bridge_sources: int = 0
    ai_state: str = "OFFLINE"
    ai_bias: str = ""
    ai_risk: str = ""
    ai_summary: str = ""
    configured_sources: int = 0
    ready: bool = False
    checks: list[CheckItem] = field(default_factory=list)
    blockers: list[str] = field(default_factory=list)

    @property
    def healthy(self) -> bool:
        """True when ON is actually delivering signals end to end."""
        return self.enabled and self.ea_online and self.ea_demo and self.bridge_running

    @property
    def headline(self) -> str:
        if not self.enabled:
            return "SYSTEM OFF"
        return "SYSTEM ON" if self.healthy else "SYSTEM BLOCKED"


def _read_json(name: str) -> dict | None:
    try:
        raw = (paths.nixo_common_dir() / name).read_text(encoding="utf-8")
        value = json.loads(raw)
    except (OSError, ValueError):
        return None
    return value if isinstance(value, dict) else None


def _fresh(payload: dict | None, key: str, max_age: int) -> bool:
    if not payload:
        return False
    try:
        age = time.time() - int(payload[key])
    except (KeyError, TypeError, ValueError):
        return False
    return 0 <= age <= max_age


def _read_ai_status() -> tuple[str, str, str, str]:
    try:
        raw = (paths.nixo_common_dir() / "ai_status.txt").read_text(
            encoding="ascii", errors="replace"
        ).strip()
    except OSError:
        return "OFFLINE", "", "", "AI bridge not started"
    parts = raw.split("|")
    if len(parts) < 5:
        return "OFFLINE", "", "", "AI bridge not started"
    return parts[0], parts[2], parts[3], parts[4]


def _load_control() -> tuple[bool, bool]:
    """Return (enabled, valid) for the control file the EA consumes."""
    if str(paths.ROOT) not in sys.path:
        sys.path.insert(0, str(paths.ROOT))
    from bridge.control_protocol import control_enabled, load_control

    try:
        control = load_control(paths.nixo_common_dir() / "control.json")
    except (OSError, ValueError):
        return False, False
    return control_enabled(control), True


def collect() -> Snapshot:
    snapshot = Snapshot()
    snapshot.enabled, snapshot.control_valid = _load_control()

    ea = _read_json("ea_status.json")
    snapshot.ea_online = _fresh(ea, "heartbeat", EA_HEARTBEAT_MAX_AGE)
    if ea:
        snapshot.ea_demo = ea.get("demo_account") is True
        snapshot.ea_running = ea.get("running") is True
        snapshot.ea_version = str(ea.get("ea_version", ""))
        snapshot.ea_mode = str(ea.get("trading_mode", "Unknown"))
        snapshot.ea_live = ea.get("signal_live_enabled") is True
        snapshot.ea_signal_lab = ea.get("signal_lab_enabled") is True
        snapshot.ea_symbol = str(ea.get("symbol", ""))

    bridge = read_status("bridge_status.json")
    snapshot.bridge_running = bool(
        bridge and bridge.get("running") and _fresh(bridge, "last_heartbeat", BRIDGE_HEARTBEAT_MAX_AGE)
    )
    if bridge:
        try:
            snapshot.bridge_sources = int(bridge.get("active_sources", 0))
        except (TypeError, ValueError):
            snapshot.bridge_sources = 0

    state, bias, risk, summary = _read_ai_status()
    snapshot.ai_state, snapshot.ai_bias = state, bias
    snapshot.ai_risk, snapshot.ai_summary = risk, summary

    snapshot.configured_sources = len(enabled_telegram_sources())
    snapshot.checks = readiness()
    snapshot.ready = is_ready()

    if snapshot.enabled:
        if not snapshot.ea_online:
            snapshot.blockers.append("Nixo EA heartbeat is missing — open MT5 and attach the EA.")
        elif not snapshot.ea_demo:
            snapshot.blockers.append("The attached account is not Demo. Live trading stays blocked.")
        elif not snapshot.ea_signal_lab:
            snapshot.blockers.append("InpSignalLabEnabled is off — enable it and reload the EA.")
        elif not snapshot.bridge_running:
            snapshot.blockers.append("Signal Bridge is not running yet.")
    elif not snapshot.ready:
        snapshot.blockers.append("Setup is incomplete — open Setup and fill the required fields.")
    return snapshot
