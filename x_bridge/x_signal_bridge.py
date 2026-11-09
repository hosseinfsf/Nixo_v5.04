#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Nixo X Signal Bridge (نسخه یکپارچه)
-----------------------------------
- پشتیبانی از چند حساب
- پارس قوی Rule-based + لایه AI (Groq)
- نوشتن مستقیم در inbox اکسپرت Nixo
"""

import os
import sys
import json
import time
import logging
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, List, Optional

import requests
from dotenv import load_dotenv

# ------------------------------------------------------------------
# اضافه کردن مسیر shared
# ------------------------------------------------------------------
ROOT = Path(__file__).parent.parent.resolve()
sys.path.insert(0, str(ROOT))

from shared.signal_parser import parse_signal
from shared.models import Signal

# ------------------------------------------------------------------
# لاگ
# ------------------------------------------------------------------
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)-7s | %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S"
)
log = logging.getLogger("NixoXBridge")

# ------------------------------------------------------------------
# بارگذاری تنظیمات
# ------------------------------------------------------------------
BASE_DIR = Path(__file__).parent.resolve()
load_dotenv(BASE_DIR / ".env.local")
load_dotenv(BASE_DIR / ".env")

BEARER_TOKEN = os.getenv("X_BEARER_TOKEN", "").strip()
MT5_COMMON_OVERRIDE = os.getenv("MT5_COMMON_FILES", "").strip()
CONFIG_PATH = BASE_DIR / "config_x.json"


def load_config() -> dict:
    with open(CONFIG_PATH, "r", encoding="utf-8") as f:
        return json.load(f)


def get_headers() -> dict:
    if not BEARER_TOKEN or BEARER_TOKEN.startswith("YOUR_"):
        raise ValueError("X_BEARER_TOKEN تنظیم نشده است")
    return {
        "Authorization": f"Bearer {BEARER_TOKEN}",
        "User-Agent": "NixoXBridge/2.0"
    }


def find_mt5_inbox() -> Path:
    if MT5_COMMON_OVERRIDE:
        p = Path(MT5_COMMON_OVERRIDE) / "NixoBridge" / "inbox"
        p.mkdir(parents=True, exist_ok=True)
        return p

    candidates = [
        Path(os.environ.get("APPDATA", "")) / "MetaQuotes" / "Terminal" / "Common" / "Files" / "NixoBridge" / "inbox",
        Path.home() / "AppData" / "Roaming" / "MetaQuotes" / "Terminal" / "Common" / "Files" / "NixoBridge" / "inbox",
    ]
    for c in candidates:
        if c.parent.parent.exists():
            c.mkdir(parents=True, exist_ok=True)
            return c

    fallback = BASE_DIR / "inbox"
    fallback.mkdir(exist_ok=True)
    log.warning(f"مسیر MT5 پیدا نشد → استفاده از: {fallback}")
    return fallback


def get_user_id(username: str) -> Optional[str]:
    url = f"https://api.twitter.com/2/users/by/username/{username}"
    try:
        r = requests.get(url, headers=get_headers(), timeout=12)
        if r.status_code == 200:
            return r.json().get("data", {}).get("id")
        log.warning(f"@{username} resolve نشد | {r.status_code}")
    except Exception as e:
        log.warning(f"خطا در resolve @{username}: {e}")
    return None


def fetch_recent_tweets(user_id: str, max_results: int = 8) -> List[dict]:
    url = f"https://api.twitter.com/2/users/{user_id}/tweets"
    params = {
        "max_results": min(max_results, 100),
        "tweet.fields": "created_at,text",
        "exclude": "retweets"
    }
    try:
        r = requests.get(url, headers=get_headers(), params=params, timeout=12)
        if r.status_code == 200:
            return r.json().get("data", [])
        log.warning(f"خطا در دریافت توییت | {r.status_code} | {r.text[:150]}")
    except Exception as e:
        log.warning(f"خطا در fetch: {e}")
    return []


def write_to_inbox(inbox: Path, signal: Signal):
    ts = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S_%f")
    safe_source = signal.source.replace(":", "_").replace("/", "_")
    filename = f"x_{safe_source}_{ts}.json"
    path = inbox / filename

    with open(path, "w", encoding="utf-8") as f:
        f.write(signal.to_nixo_json())

    log.info(f"✓ سیگنال ثبت شد | {signal.side} {signal.symbol} @ {signal.entry} | "
             f"parser={signal.parser} | conf={signal.confidence:.2f} | {filename}")


def main():
    log.info("=" * 55)
    log.info("  Nixo X Signal Bridge v2.0 (Rule + AI)")
    log.info("=" * 55)

    if not BEARER_TOKEN or BEARER_TOKEN.startswith("YOUR_"):
        log.error("X_BEARER_TOKEN را در فایل .env.local تنظیم کنید")
        return

    config = load_config()
    settings = config.get("settings", {})
    accounts = config.get("accounts", [])

    poll_interval = int(settings.get("poll_interval_seconds", 25))
    max_posts = int(settings.get("max_posts_per_account", 8))
    use_ai = bool(settings.get("use_ai_fallback", True))
    ai_provider = settings.get("ai_provider", "groq")
    default_symbols = settings.get("default_symbols", ["XAUUSD"])

    inbox = find_mt5_inbox()
    log.info(f"Inbox → {inbox}")
    log.info(f"AI Fallback → {'فعال' if use_ai else 'غیرفعال'} ({ai_provider})")

    # Resolve user IDs
    user_map: Dict[str, dict] = {}  # username -> {id, allowed_symbols}
    for acc in accounts:
        if not acc.get("enabled"):
            continue
        username = acc.get("username", "").lstrip("@").strip()
        if not username:
            continue

        uid = acc.get("user_id") or get_user_id(username)
        if uid:
            user_map[username] = {
                "id": uid,
                "allowed": acc.get("allowed_symbols") or default_symbols
            }
            log.info(f"فعال: @{username} → {uid}")
        else:
            log.warning(f"نتوانست @{username} را پیدا کند")

    if not user_map:
        log.error("هیچ حساب فعالی وجود ندارد. config_x.json را بررسی کنید.")
        return

    last_seen: Dict[str, str] = {}
    log.info(f"شروع مانیتورینگ هر {poll_interval} ثانیه...\n")

    while True:
        try:
            for username, info in user_map.items():
                tweets = fetch_recent_tweets(info["id"], max_posts)

                for tw in tweets:
                    tw_id = tw.get("id")
                    text = tw.get("text", "")

                    # جلوگیری از پردازش تکراری و سیگنال‌های قدیمی در اولین اجرا
                    if username not in last_seen:
                        last_seen[username] = tw_id
                        continue
                    if last_seen.get(username) == tw_id:
                        break

                    signal = parse_signal(
                        text=text,
                        source=f"x:{username}",
                        allowed_symbols=info["allowed"],
                        use_ai_fallback=use_ai,
                        ai_provider=ai_provider
                    )

                    if signal and signal.is_valid():
                        write_to_inbox(inbox, signal)
                    else:
                        log.debug(f"@{username} | قابل پارس نبود: {text[:70]}...")

                if tweets:
                    last_seen[username] = tweets[0]["id"]

            time.sleep(poll_interval)

        except KeyboardInterrupt:
            log.info("\nتوقف توسط کاربر")
            break
        except Exception as e:
            log.exception(f"خطا: {e}")
            time.sleep(15)


if __name__ == "__main__":
    main()
