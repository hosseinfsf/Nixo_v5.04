"""Persistence layer for config/sources.json.

All signal-source edits go through here so the GUI never writes JSON by hand.
"""
from __future__ import annotations

import json
import os
import re
import tempfile
from pathlib import Path
from typing import Any

from .paths import CONFIG_FILE

SOURCE_TYPES = ("telegram", "rss", "x", "tradingview")
USERNAME_PATTERN = re.compile(r"[A-Za-z0-9_]{3,}")
SYMBOL_PATTERN = re.compile(r"[A-Z0-9._-]{1,32}")


class SourceError(ValueError):
    """Raised when a requested source edit cannot be applied."""


def load_config() -> dict[str, Any]:
    try:
        data = json.loads(CONFIG_FILE.read_text(encoding="utf-8"))
    except FileNotFoundError:
        data = {}
    except (OSError, ValueError) as exc:
        raise SourceError(f"config/sources.json is unreadable: {exc}") from exc
    if not isinstance(data, dict):
        raise SourceError("config/sources.json must contain a JSON object")
    data.setdefault("session_name", "nixo_telegram")
    data.setdefault("mt5_common_files", "")
    if not isinstance(data.get("sources"), list):
        data["sources"] = []
    return data


def save_config(data: dict[str, Any]) -> None:
    CONFIG_FILE.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=".sources.", suffix=".tmp", dir=CONFIG_FILE.parent
    )
    temporary_path = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8", newline="\n") as handle:
            json.dump(data, handle, ensure_ascii=False, indent=2)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary_path, CONFIG_FILE)
    except BaseException:
        temporary_path.unlink(missing_ok=True)
        raise


def source_id_for(channel: str) -> str:
    cleaned = re.sub(r"[^A-Za-z0-9_-]+", "_", channel.strip().lstrip("@"))
    return (cleaned[:32] or "source")


def parse_symbols(raw: str) -> list[str]:
    symbols = [part.strip().upper() for part in raw.split(",") if part.strip()]
    unique = list(dict.fromkeys(symbols))
    invalid = [symbol for symbol in unique if not SYMBOL_PATTERN.fullmatch(symbol)]
    if invalid:
        raise SourceError(f"Invalid symbol(s): {', '.join(invalid)}")
    return unique


def telegram_sources(data: dict[str, Any]) -> list[dict[str, Any]]:
    return [
        source for source in data["sources"]
        if str(source.get("source_type", "telegram")).lower() == "telegram"
    ]


def find_source(data: dict[str, Any], source_id: str) -> dict[str, Any] | None:
    return next((item for item in data["sources"] if str(item.get("id")) == source_id), None)


def upsert_telegram(
    data: dict[str, Any],
    name: str,
    channel: str,
    symbols: list[str],
    enabled: bool,
    assume_single_symbol: bool,
    existing_id: str | None = None,
) -> str:
    """Create or update a Telegram source and return its id."""
    channel = channel.strip().lstrip("@")
    if not name.strip():
        raise SourceError("Display name is required.")
    channel_id: int | None = None
    if channel.startswith("-100") and channel[4:].isdigit():
        channel_id = int(channel[4:])
    elif channel.isdigit():
        channel_id = int(channel)
    elif not USERNAME_PATTERN.fullmatch(channel):
        raise SourceError(
            "Enter a public Telegram username or a numeric channel ID. "
            "For private channels, join the channel first; invite links are not supported."
        )
    if channel_id is not None and channel_id <= 0:
        raise SourceError("Telegram channel ID must be a positive number.")
    if not symbols:
        raise SourceError("At least one allowed symbol is required.")

    locator = f"private_{channel_id}" if channel_id is not None else channel
    new_id = existing_id or source_id_for(locator)
    if existing_id is None and find_source(data, new_id) is not None:
        raise SourceError(f"A source with id '{new_id}' already exists.")

    record: dict[str, Any] = {
        "id": new_id,
        "name": name.strip(),
        "source_type": "telegram",
        "enabled": enabled,
        "parser": "standard",
        "allowed_symbols": symbols,
        "assume_single_symbol": bool(assume_single_symbol) and len(symbols) == 1,
    }
    if channel_id is not None:
        record["channel_id"] = channel_id
    else:
        record["channel"] = channel
    if existing_id is not None:
        current = find_source(data, existing_id)
        if current is None:
            raise SourceError(f"Source '{existing_id}' no longer exists.")
        current.pop("channel", None)
        current.pop("channel_id", None)
        current.update(record)
    else:
        data["sources"].append(record)
    save_config(data)
    return new_id


def set_enabled(source_id: str, enabled: bool) -> None:
    data = load_config()
    source = find_source(data, source_id)
    if source is None:
        raise SourceError(f"Source '{source_id}' no longer exists.")
    source["enabled"] = enabled
    save_config(data)


def remove(source_id: str) -> None:
    data = load_config()
    if find_source(data, source_id) is None:
        raise SourceError(f"Source '{source_id}' no longer exists.")
    data["sources"] = [
        item for item in data["sources"] if str(item.get("id")) != source_id
    ]
    save_config(data)
