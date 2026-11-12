"""Helpers for NixoBridge control.json and ea_status.json (fail-closed)."""
from __future__ import annotations

import json
import os
import time
from pathlib import Path
from typing import Any, Optional

CONTROL_NAME = "control.json"
EA_STATUS_NAME = "ea_status.json"
DEFAULT_STALE_SECONDS = 15


def resolve_common_files(configured: str | None = None) -> Path:
    configured = (configured or os.environ.get("MT5_COMMON_FILES", "")).strip()
    if configured:
        return Path(configured).expanduser().resolve()
    appdata = os.environ.get("APPDATA", "").strip()
    if appdata:
        return Path(appdata) / "MetaQuotes" / "Terminal" / "Common" / "Files"
    raise RuntimeError("Set MT5_COMMON_FILES to the MT5 Common\\Files folder.")


def nixo_bridge_dir(common: Path) -> Path:
    path = common / "NixoBridge"
    path.mkdir(parents=True, exist_ok=True)
    return path


def control_path(common: Path) -> Path:
    return nixo_bridge_dir(common) / CONTROL_NAME


def ea_status_path(common: Path) -> Path:
    return nixo_bridge_dir(common) / EA_STATUS_NAME


def default_control(sources: Optional[list[dict[str, Any]]] = None) -> dict[str, Any]:
    return {
        "master_armed": False,
        "updated_unix": int(time.time()),
        "sources": list(sources or []),
    }


def write_control(common: Path, data: dict[str, Any]) -> Path:
    payload = dict(data)
    payload["updated_unix"] = int(time.time())
    if "master_armed" not in payload:
        payload["master_armed"] = False
    if "sources" not in payload or not isinstance(payload["sources"], list):
        payload["sources"] = []
    target = control_path(common)
    tmp = target.with_suffix(".tmp")
    tmp.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    os.replace(tmp, target)
    return target


def read_control(common: Path) -> Optional[dict[str, Any]]:
    path = control_path(common)
    if not path.exists():
        return None
    try:
        data = json.loads(path.read_text(encoding="utf-8-sig"))
    except (OSError, json.JSONDecodeError, UnicodeError):
        return None
    if not isinstance(data, dict):
        return None
    if "master_armed" not in data:
        return None
    if not isinstance(data.get("sources", []), list):
        return None
    return data


def is_master_armed(common: Path) -> bool:
    data = read_control(common)
    if data is None:
        return False
    return bool(data.get("master_armed"))


def write_ea_status(common: Path, status: dict[str, Any]) -> Path:
    payload = dict(status)
    payload["unix"] = int(time.time())
    target = ea_status_path(common)
    tmp = target.with_suffix(".tmp")
    tmp.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    os.replace(tmp, target)
    return target


def read_ea_status(common: Path) -> Optional[dict[str, Any]]:
    path = ea_status_path(common)
    if not path.exists():
        return None
    try:
        data = json.loads(path.read_text(encoding="utf-8-sig"))
    except (OSError, json.JSONDecodeError, UnicodeError):
        return None
    if not isinstance(data, dict) or "unix" not in data:
        return None
    return data


def ea_status_fresh(common: Path, max_age: int = DEFAULT_STALE_SECONDS) -> bool:
    data = read_ea_status(common)
    if data is None:
        return False
    try:
        age = time.time() - float(data["unix"])
    except (TypeError, ValueError, KeyError):
        return False
    return age <= max_age


def allow_new_intake(common: Path, max_age: int = DEFAULT_STALE_SECONDS) -> tuple[bool, str]:
    """Fail-closed gate for NEW signal intake."""
    control = read_control(common)
    if control is None:
        return False, "control.json missing or malformed"
    if not bool(control.get("master_armed")):
        return False, "master_armed is OFF"
    if not ea_status_fresh(common, max_age=max_age):
        return False, f"ea_status heartbeat stale (>{max_age}s) or missing"
    status = read_ea_status(common) or {}
    trade_mode = str(status.get("trade_mode", "")).upper()
    if trade_mode and trade_mode != "DEMO":
        return False, f"account trade_mode={trade_mode} (Demo required)"
    return True, "ok"


def sources_from_config(config_path: Path) -> list[dict[str, Any]]:
    if not config_path.exists():
        return []
    try:
        cfg = json.loads(config_path.read_text(encoding="utf-8-sig"))
    except (OSError, json.JSONDecodeError):
        return []
    out: list[dict[str, Any]] = []
    for src in cfg.get("sources", []) or []:
        if not isinstance(src, dict):
            continue
        out.append({
            "id": str(src.get("id", "")),
            "enabled": bool(src.get("enabled")),
            "channel": str(src.get("channel", "")),
            "name": str(src.get("name", src.get("id", ""))),
            "allowed_symbols": list(src.get("allowed_symbols") or []),
            "source_type": str(src.get("source_type", "telegram")),
        })
    return out
