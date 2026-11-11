"""Filesystem discovery for the Nixo Control Center.

Every path the Control Center needs is resolved here so the rest of the
package never guesses at Windows layout.
"""
from __future__ import annotations

import json
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BRIDGE_DIR = ROOT / "bridge"
AI_BRIDGE_DIR = ROOT / "ai_bridge"
CONFIG_DIR = ROOT / "config"
CONFIG_FILE = CONFIG_DIR / "sources.json"
MT5_SOURCE_DIR = ROOT / "mt5"
DEFAULT_EA_NAME = "Nixo_v5.05_Merged_TradingModes_Theme_FA_EN"

ENV_KEYS_OF_INTEREST = (
    "MT5_COMMON_FILES",
    "TELEGRAM_API_ID",
    "TELEGRAM_API_HASH",
)


def appdata_dir() -> Path:
    return Path(os.environ.get("APPDATA") or Path.home() / "AppData" / "Roaming")


def default_common_files() -> Path:
    return appdata_dir() / "MetaQuotes" / "Terminal" / "Common" / "Files"


def read_env_file(path: Path) -> dict[str, str]:
    """Parse a simple KEY=VALUE file, ignoring comments and blanks."""
    values: dict[str, str] = {}
    try:
        raw_lines = path.read_text(encoding="utf-8-sig").splitlines()
    except (FileNotFoundError, OSError):
        return values
    for raw in raw_lines:
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        if key:
            values[key] = value.strip().strip("\"'")
    return values


def write_env_file(path: Path, values: dict[str, str], header: str = "") -> None:
    """Rewrite an env file atomically, preserving a short comment header."""
    path.parent.mkdir(parents=True, exist_ok=True)
    lines: list[str] = []
    if header:
        lines.extend(f"# {part}" for part in header.splitlines())
    for key, value in values.items():
        lines.append(f"{key}={value}")
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text("\n".join(lines) + "\n", encoding="utf-8")
    os.replace(temporary, path)


def resolve_common_files() -> Path:
    """Locate the MT5 Common\\Files folder, honouring explicit configuration."""
    configured = os.environ.get("MT5_COMMON_FILES", "").strip()
    if not configured:
        configured = read_env_file(BRIDGE_DIR / ".env.local").get("MT5_COMMON_FILES", "")
    if not configured:
        try:
            config = json.loads(CONFIG_FILE.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            config = {}
        if isinstance(config, dict):
            configured = str(config.get("mt5_common_files", "") or "").strip()
    if configured:
        return Path(configured).expanduser().resolve()
    return default_common_files()


def nixo_common_dir() -> Path:
    """The NixoBridge handshake folder inside MT5 Common Files."""
    return resolve_common_files() / "NixoBridge"


def terminal_data_dirs() -> list[Path]:
    """Every per-terminal MT5 data folder that already holds an MQL5 tree."""
    base = appdata_dir() / "MetaQuotes" / "Terminal"
    found: list[Path] = []
    try:
        entries = list(base.iterdir())
    except (FileNotFoundError, OSError):
        return found
    for entry in entries:
        if entry.is_dir() and (entry / "MQL5").is_dir():
            found.append(entry)
    return sorted(found)


def find_terminal_icon(data_dir: Path) -> Path | None:
    """Return the terminal executable recorded in a data folder's origin.txt."""
    origin = data_dir / "origin.txt"
    try:
        raw = origin.read_text(encoding="utf-16").strip().strip("\x00")
    except (FileNotFoundError, OSError, UnicodeError):
        return None
    if not raw:
        return None
    candidate = Path(raw)
    executable = candidate / "terminal64.exe"
    return executable if executable.is_file() else None
