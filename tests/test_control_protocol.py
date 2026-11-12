"""Tests for shared.control_protocol fail-closed helpers."""
from __future__ import annotations

import json
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from shared.control_protocol import (  # noqa: E402
    allow_new_intake,
    default_control,
    is_master_armed,
    read_control,
    write_control,
    write_ea_status,
)


def test_default_control_is_disarmed():
    data = default_control()
    assert data["master_armed"] is False
    assert isinstance(data["sources"], list)


def test_missing_control_fail_closed(tmp_path: Path):
    ok, reason = allow_new_intake(tmp_path)
    assert ok is False
    assert "control" in reason.lower() or "missing" in reason.lower()


def test_armed_requires_fresh_demo_status(tmp_path: Path):
    write_control(tmp_path, default_control())
    assert is_master_armed(tmp_path) is False
    write_control(tmp_path, {"master_armed": True, "sources": []})
    assert is_master_armed(tmp_path) is True
    ok, reason = allow_new_intake(tmp_path)
    assert ok is False
    assert "heartbeat" in reason.lower() or "stale" in reason.lower() or "ea_status" in reason.lower()

    write_ea_status(tmp_path, {
        "account_login": 1,
        "trade_mode": "DEMO",
        "trading_mode": "EXTERNAL SIGNALS",
        "signal_live": True,
        "symbol": "XAUUSD",
        "open_positions": 0,
        "pending_orders": 0,
    })
    ok, reason = allow_new_intake(tmp_path)
    assert ok is True, reason


def test_real_account_blocked(tmp_path: Path):
    write_control(tmp_path, {"master_armed": True, "sources": []})
    write_ea_status(tmp_path, {"trade_mode": "REAL", "symbol": "XAUUSD"})
    ok, reason = allow_new_intake(tmp_path)
    assert ok is False
    assert "demo" in reason.lower() or "real" in reason.lower()


def test_malformed_control_fail_closed(tmp_path: Path):
    path = tmp_path / "NixoBridge"
    path.mkdir(parents=True)
    (path / "control.json").write_text("{not-json", encoding="utf-8")
    assert read_control(tmp_path) is None
    ok, _ = allow_new_intake(tmp_path)
    assert ok is False


def test_atomic_write_roundtrip(tmp_path: Path):
    write_control(tmp_path, {"master_armed": True, "sources": [{"id": "a", "enabled": True}]})
    data = read_control(tmp_path)
    assert data is not None
    assert data["master_armed"] is True
    assert data["sources"][0]["id"] == "a"
    raw = json.loads((tmp_path / "NixoBridge" / "control.json").read_text(encoding="utf-8"))
    assert "updated_unix" in raw
    assert abs(raw["updated_unix"] - time.time()) < 5
