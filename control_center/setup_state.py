"""Configuration persistence and readiness checks for first-run setup."""
from __future__ import annotations

import json
import os
from dataclasses import dataclass
from pathlib import Path

from .paths import (
    AI_BRIDGE_DIR,
    BRIDGE_DIR,
    CONFIG_FILE,
    read_env_file,
    resolve_common_files,
    write_env_file,
)

BRIDGE_ENV = BRIDGE_DIR / ".env.local"
AI_ENV = AI_BRIDGE_DIR / ".env.local"
TELEGRAM_SESSION = BRIDGE_DIR / "nixo_telegram.session"

DEFAULT_BRIDGE_ENV: dict[str, str] = {
    "TELEGRAM_API_ID": "",
    "TELEGRAM_API_HASH": "",
    "MT5_COMMON_FILES": "",
    "X_BEARER_TOKEN": "",
    "NIXO_X_POLL_SECONDS": "60",
    "NIXO_TV_WEBHOOK_SECRET": "",
    "NIXO_TV_WEBHOOK_HOST": "127.0.0.1",
    "NIXO_TV_WEBHOOK_PORT": "8765",
}

DEFAULT_AI_ENV: dict[str, str] = {
    "NIXO_AI_BASE_URL": "https://api.groq.com/openai/v1/chat/completions",
    "NIXO_AI_MODEL": "llama-3.3-70b-versatile",
    "NIXO_AI_API_KEY": "",
    "NIXO_AI_REFRESH_SECONDS": "30",
    "NIXO_AI_TIMEOUT_SECONDS": "25",
}


@dataclass
class CheckItem:
    key: str
    title: str
    ok: bool
    detail: str
    required: bool = True


def bridge_env() -> dict[str, str]:
    """Existing bridge credentials merged over the defaults."""
    values = dict(DEFAULT_BRIDGE_ENV)
    values.update({k: v for k, v in read_env_file(BRIDGE_ENV).items() if k in values})
    return values


def ai_env() -> dict[str, str]:
    values = dict(DEFAULT_AI_ENV)
    values.update({k: v for k, v in read_env_file(AI_ENV).items() if k in values})
    return values


def save_bridge_env(values: dict[str, str]) -> None:
    write_env_file(
        BRIDGE_ENV,
        {key: values.get(key, "") for key in DEFAULT_BRIDGE_ENV},
        header="Nixo Signal Bridge credentials. Keep this file local and never commit it.",
    )


def save_ai_env(values: dict[str, str]) -> None:
    write_env_file(
        AI_ENV,
        {key: values.get(key, "") for key in DEFAULT_AI_ENV},
        header="Nixo AI advisory bridge. Keep this file local and never commit it.",
    )


def configured_sources() -> list[dict]:
    try:
        data = json.loads(CONFIG_FILE.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return []
    sources = data.get("sources") if isinstance(data, dict) else None
    return sources if isinstance(sources, list) else []


def enabled_telegram_sources() -> list[dict]:
    return [
        source for source in configured_sources()
        if source.get("enabled")
        and str(source.get("source_type", "telegram")).lower() == "telegram"
    ]


def readiness() -> list[CheckItem]:
    """The ordered checklist the setup panel shows."""
    env = bridge_env()
    common = resolve_common_files()
    telegram_enabled = bool(enabled_telegram_sources())
    has_credentials = bool(env["TELEGRAM_API_ID"]) and bool(env["TELEGRAM_API_HASH"])
    has_session = TELEGRAM_SESSION.exists()
    ai_values = ai_env()

    return [
        CheckItem(
            "mt5",
            "MetaTrader 5 data folder",
            common.is_dir(),
            str(common),
            required=False,
        ),
        CheckItem(
            "telegram_api",
            "Telegram API credentials",
            has_credentials,
            "Saved in bridge/.env.local" if has_credentials else "Set api_id and api_hash from my.telegram.org",
        ),
        CheckItem(
            "sources",
            "Enabled Telegram channel",
            telegram_enabled,
            f"{len(enabled_telegram_sources())} enabled" if telegram_enabled else "Add at least one channel",
        ),
        CheckItem(
            "session",
            "Telegram login session",
            has_session,
            "Saved" if has_session else "First ON press opens a console for the code prompt",
            required=False,
        ),
        CheckItem(
            "ai",
            "AI advisory bridge (optional)",
            bool(ai_values["NIXO_AI_API_KEY"]),
            "Configured" if ai_values["NIXO_AI_API_KEY"] else "Optional - skip unless you want an AI bias panel",
            required=False,
        ),
    ]


def is_ready() -> bool:
    return all(item.ok for item in readiness() if item.required)


def open_in_explorer(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)
    if os.name == "nt":
        os.startfile(str(path))
