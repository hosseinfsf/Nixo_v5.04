#!/usr/bin/env python3
"""Local add/edit/remove manager for Telegram and RSS/Atom signal sources."""
from __future__ import annotations
import json
import re
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parent
CONFIG = ROOT.parent / "config" / "sources.json"


def load():
    data = json.loads(CONFIG.read_text(encoding="utf-8"))
    data.setdefault("sources", [])
    return data


def save(data):
    tmp = CONFIG.with_suffix(".tmp")
    tmp.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    tmp.replace(CONFIG)


def source_id(value: str) -> str:
    return re.sub(r"[^a-zA-Z0-9_-]+", "_", value.strip().lstrip("@"))[:32] or "source"


def yes(prompt: str, default=True) -> bool:
    raw = input(f"{prompt} [{'Y/n' if default else 'y/N'}]: ").strip().lower()
    if not raw:
        return default
    return raw in {"y", "yes", "1", "true"}


def source_type(source: dict) -> str:
    return str(source.get("source_type", "telegram")).lower()


def list_sources(data):
    print("\nConfigured signal sources:")
    if not data["sources"]:
        print("  (none)")
    for i, s in enumerate(data["sources"], 1):
        st = source_type(s)
        endpoint = ("@" + str(s.get("channel", ""))) if st == "telegram" else str(s.get("feed_url", ""))
        print(f"  {i}. {'ON ' if s.get('enabled') else 'OFF'} [{st.upper()}] {s.get('name')} | {endpoint} | id={s.get('id')} | symbols={','.join(s.get('allowed_symbols', []))}")
    print()


def choose(data):
    list_sources(data)
    raw = input("Source number: ").strip()
    try:
        idx = int(raw) - 1
        return idx if 0 <= idx < len(data["sources"]) else None
    except ValueError:
        return None


def parse_symbols(raw: str) -> list[str]:
    values = [x.strip().upper() for x in raw.split(",") if x.strip()]
    return list(dict.fromkeys(values))


def add_source(data):
    print("Source type: 1) Telegram channel   2) Website RSS / Atom feed")
    kind = input("> ").strip()
    if kind not in {"1", "2"}:
        print("Choose 1 or 2.")
        return
    st = "telegram" if kind == "1" else "rss"
    name = input("Display name: ").strip()
    endpoint = input("Telegram username (without @): " if st == "telegram" else "RSS/Atom feed URL (not a normal HTML page): ").strip()
    if st == "telegram":
        endpoint = endpoint.lstrip("@")
        if not endpoint or not re.fullmatch(r"[A-Za-z0-9_]{3,}", endpoint):
            print("Invalid Telegram channel username.")
            return
        identity = endpoint
    else:
        parsed = urlparse(endpoint)
        if parsed.scheme not in {"http", "https"} or not parsed.netloc:
            print("Feed URL must be a valid http(s) RSS/Atom URL.")
            return
        identity = parsed.netloc + parsed.path
    sid_default = source_id(identity.split("/")[-1])
    sid = source_id(input(f"Unique source ID [{sid_default}]: ").strip() or sid_default)
    if any(s.get("id") == sid for s in data["sources"]):
        print("That ID already exists.")
        return
    symbols = input("Allowed symbols, comma-separated [XAUUSD]: ").strip() or "XAUUSD"
    item = {
        "id": sid,
        "name": name or sid,
        "source_type": st,
        "enabled": yes("Enable this source now?", False),
        "parser": "standard",
        "allowed_symbols": parse_symbols(symbols),
        "assume_single_symbol": yes("Assume this source's only symbol if ticker is omitted?", False),
    }
    if st == "telegram":
        item["channel"] = endpoint
    else:
        item["feed_url"] = endpoint
        item["poll_seconds"] = 45
    data["sources"].append(item)
    save(data)
    print("Source saved. Restart the signal bridge to apply it.")


def edit_source(data):
    idx = choose(data)
    if idx is None:
        print("No valid source selected.")
        return
    s = data["sources"][idx]
    st = source_type(s)
    value = input(f"Name [{s.get('name','')}]: ").strip()
    if value:
        s["name"] = value
    if st == "telegram":
        value = input(f"Channel [{s.get('channel','')}]: ").strip().lstrip("@")
        if value:
            if not re.fullmatch(r"[A-Za-z0-9_]{3,}", value):
                print("Invalid Telegram channel username; keeping the previous value.")
            else:
                s["channel"] = value
    else:
        value = input(f"Feed URL [{s.get('feed_url','')}]: ").strip()
        if value:
            parsed = urlparse(value)
            if parsed.scheme in {"http", "https"} and parsed.netloc:
                s["feed_url"] = value
            else:
                print("Invalid URL; keeping the previous feed URL.")
    value = input(f"Allowed symbols [{','.join(s.get('allowed_symbols', []))}]: ").strip()
    if value:
        s["allowed_symbols"] = parse_symbols(value)
    s["enabled"] = yes("Enable source?", bool(s.get("enabled")))
    s["assume_single_symbol"] = yes("Assume the only allowed symbol when ticker is omitted?", bool(s.get("assume_single_symbol")))
    save(data)
    print("Source updated. Restart the signal bridge to apply it.")


def toggle_source(data):
    idx = choose(data)
    if idx is None:
        print("No valid source selected.")
        return
    s = data["sources"][idx]
    s["enabled"] = not bool(s.get("enabled"))
    save(data)
    print(f"{s.get('name')} is now {'ENABLED' if s['enabled'] else 'DISABLED'}. Restart the bridge to apply it.")


def remove_source(data):
    idx = choose(data)
    if idx is None:
        print("No valid source selected.")
        return
    s = data["sources"][idx]
    if yes(f"Permanently remove {s.get('name')}?", False):
        data["sources"].pop(idx)
        save(data)
        print("Source removed. Restart the bridge to apply it.")


def main():
    print("NIXO SIGNAL SOURCE MANAGER (local only)")
    print("Add Telegram channels or RSS/Atom website feeds. Normal HTML pages need a site-specific adapter.")
    print("Edits config/sources.json; restart the bridge to apply changes.\n")
    while True:
        print("1) List   2) Add   3) Edit   4) Enable/Disable   5) Remove   0) Exit")
        choice = input("> ").strip()
        data = load()
        if choice == "1": list_sources(data)
        elif choice == "2": add_source(data)
        elif choice == "3": edit_source(data)
        elif choice == "4": toggle_source(data)
        elif choice == "5": remove_source(data)
        elif choice == "0": break
        else: print("Choose 0–5.")


if __name__ == "__main__":
    main()
