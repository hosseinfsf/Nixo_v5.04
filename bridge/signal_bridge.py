#!/usr/bin/env python3
"""Nixo Signal Bridge (local Telegram + RSS/Atom reader -> MT5 Common Files inbox).

This bridge only reads channels that the signed-in Telegram account can access.
It never places trades. MT5/Nixo decides whether a signal is paper-tested or copied.
"""
from __future__ import annotations

import argparse
import asyncio
import hashlib
import html
import json
import logging
import os
import re
import sys
import time
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET
from email.utils import parsedate_to_datetime
from datetime import datetime
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Optional, Any

APP_NAME = "Nixo Signal Bridge"
VERSION = "0.2.0"
ROOT = Path(__file__).resolve().parent
DEFAULT_CONFIG = ROOT.parent / "config" / "sources.json"
STATE_FILE = ROOT / "bridge_state.json"
LOG_FILE = ROOT / "signal_bridge.log"
ENV_FILE = ROOT / ".env.local"

# Optional control-protocol gate import (available at runtime).
try:
    import sys as _sys
    _sys.path.insert(0, str(ROOT.parent))
    from shared.control_protocol import allow_new_intake
except Exception:  # pragma: no cover - gate checked at runtime
    allow_new_intake = None  # type: ignore

def load_local_env(path: Path = ENV_FILE) -> None:
    """Load simple KEY=VALUE entries without adding a dotenv dependency."""
    if not path.exists():
        return
    for raw in path.read_text(encoding="utf-8-sig").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip().strip('\"').strip("'")
        if key and value:
            os.environ.setdefault(key, value)

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)s | %(message)s",
    handlers=[logging.StreamHandler(sys.stdout), logging.FileHandler(LOG_FILE, encoding="utf-8")],
)
log = logging.getLogger("nixo_bridge")

NUMBER = r"([0-9]{1,6}(?:[.,][0-9]{1,8})?)"

@dataclass
class ParsedSignal:
    symbol: str
    side: str
    order_kind: str
    entry: float
    sl: float
    tp1: float
    tp2: float
    tp3: float

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


def norm_num(value: str) -> float:
    value = value.strip()
    if "," in value and "." in value:
        value = value.replace(",", "")
    else:
        value = value.replace(",", ".")
    return float(value)


def clean_source_id(value: str) -> str:
    value = re.sub(r"[^a-zA-Z0-9_-]+", "_", value.strip().lstrip("@"))
    return value[:32] or "source"


def load_config(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as f:
        cfg = json.load(f)
    if not isinstance(cfg.get("sources"), list):
        raise ValueError("config.sources must be a list")
    return cfg


def symbol_from_text(text: str, source: dict[str, Any]) -> Optional[str]:
    upper = text.upper()
    aliases = source.get("symbol_aliases", {
        "XAUUSD": ["XAUUSD", "XAU/USD", "GOLD", "GOLDUSD", "GOLD/USD"],
        "EURUSD": ["EURUSD", "EUR/USD"],
        "GBPUSD": ["GBPUSD", "GBP/USD"],
        "US30": ["US30", "DOW30", "DJ30"],
        "NAS100": ["NAS100", "NASDAQ", "USTEC"],
    })
    for canonical, variants in aliases.items():
        for variant in variants:
            if re.search(rf"(?<![A-Z0-9]){re.escape(variant.upper())}(?![A-Z0-9])", upper):
                allowed = [s.upper() for s in source.get("allowed_symbols", [])]
                alias_set = {str(v).upper() for v in variants}
                if allowed and canonical.upper() not in allowed and not (alias_set & set(allowed)):
                    return None
                return canonical.upper()
    allowed = [s.upper() for s in source.get("allowed_symbols", [])]
    # A source dedicated to one configured symbol may omit the ticker in its messages.
    if source.get("assume_single_symbol") and len(allowed) == 1:
        return allowed[0]
    return None


def extract_labelled(text: str, labels: list[str]) -> list[float]:
    values: list[float] = []
    for label in labels:
        pattern = rf"(?im)(?:^|[\s|]){label}\s*(?:#?\s*([1-3]))?\s*[:=@\-]?\s*{NUMBER}"
        for m in re.finditer(pattern, text):
            # If the label is TP without an ordinal, assign the next free slot.
            ordinal_text = m.group(1)
            value_text = m.group(2)
            if value_text is None:
                continue
            value = norm_num(value_text)
            if ordinal_text:
                idx = int(ordinal_text) - 1
                while len(values) <= idx:
                    values.append(0.0)
                values[idx] = value
            else:
                values.append(value)
    # Preserve order, deduplicate, maximum three targets.
    out: list[float] = []
    for v in values:
        if v > 0 and (not out or abs(out[-1] - v) > 1e-8):
            out.append(v)
    return out[:3]


def extract_one(text: str, labels: list[str]) -> float:
    for label in labels:
        m = re.search(rf"(?im)(?:^|[\s|]){label}\s*[:=@\-]?\s*{NUMBER}", text)
        if m:
            return norm_num(m.group(1))
    return 0.0


def parse_signal(text: str, source: dict[str, Any]) -> Optional[ParsedSignal]:
    """Parse common text signal templates. Ambiguous/incomplete messages are rejected."""
    if not text or len(text) > 8000:
        return None
    upper = text.upper().replace("\u200e", " ").replace("\u200f", " ")

    side = None
    # Prefer explicit action tokens; avoid mistaking 'BUY TP' etc. for a second signal.
    if re.search(r"\b(BUY|LONG)\b", upper):
        side = "BUY"
    if re.search(r"\b(SELL|SHORT)\b", upper):
        if side is None:
            side = "SELL"
        elif re.search(r"\b(BUY|LONG)\b[\s\S]*\b(SELL|SHORT)\b", upper):
            # Two directions in the same message is ambiguous, commonly a hedge/straddle.
            return None
    if side is None:
        return None

    symbol = symbol_from_text(upper, source)
    if not symbol:
        return None

    sl = extract_one(upper, [r"SL", r"STOP\s*LOSS", r"STOPLOSS"])
    tps = extract_labelled(upper, [r"TP", r"TAKE\s*PROFIT", r"TARGET"])
    if not tps:
        # Generic single target labels, but avoid reading RR ratios.
        one_tp = extract_one(upper, [r"TP", r"TAKE\s*PROFIT", r"TARGET"])
        if one_tp:
            tps = [one_tp]
    if sl <= 0 or not tps:
        return None

    entry = 0.0
    explicit_kind = ""
    entry_match = re.search(
        rf"(?im)(?:ENTRY(?:\s*ZONE)?|BUY\s*LIMIT|SELL\s*LIMIT|BUY\s*STOP|SELL\s*STOP|ENTRY\s*PRICE)\s*[:=@\-]?\s*{NUMBER}(?:\s*[-–]\s*{NUMBER})?",
        upper,
    )
    if entry_match:
        lo = norm_num(entry_match.group(1))
        hi = norm_num(entry_match.group(2)) if entry_match.group(2) else lo
        entry = (lo + hi) / 2.0
        if re.search(r"\b(?:BUY|SELL)\s*STOP\b", upper):
            explicit_kind = "STOP"
        elif re.search(r"\b(?:BUY|SELL)\s*LIMIT\b", upper):
            explicit_kind = "LIMIT"
    else:
        # Also accept compact formats such as BUY XAUUSD LIMIT 4060-4062.
        typed_entry = re.search(
            rf"(?im)\b(?:BUY|SELL)\s+(?:XAUUSD|XAU/USD|GOLD|GOLDUSD)\s+(LIMIT|STOP)\s*[:=@\-]?\s*{NUMBER}(?:\s*[-–]\s*{NUMBER})?",
            upper,
        )
        if typed_entry:
            explicit_kind = typed_entry.group(1).upper()
            lo = norm_num(typed_entry.group(2))
            hi = norm_num(typed_entry.group(3)) if typed_entry.group(3) else lo
            entry = (lo + hi) / 2.0
        else:
            # Common compact market/limit format: BUY GOLD @ 4060 or SELL XAUUSD 4060-4062.
            compact = re.search(
                rf"(?im)\b(?:BUY|SELL)\s+(?:XAUUSD|XAU/USD|GOLD|GOLDUSD)\s*(?:@|AT)?\s*{NUMBER}(?:\s*[-–]\s*{NUMBER})?",
                upper,
            )
            if compact:
                lo = norm_num(compact.group(1))
                hi = norm_num(compact.group(2)) if compact.group(2) else lo
                entry = (lo + hi) / 2.0

    if explicit_kind:
        order_kind = explicit_kind
    elif re.search(r"\b(NOW|MARKET)\b", upper) or (re.search(r"\b(BUY|SELL)\s+(?:GOLD|XAUUSD)\b", upper) and entry <= 0):
        order_kind = "MARKET"
    elif entry > 0:
        order_kind = "LIMIT"
    else:
        order_kind = "MARKET"

    # Validate directional geometry; impossible SL/TP usually means a bad parse.
    if side == "BUY":
        if any(tp <= sl for tp in tps) or any(tps[i] >= tps[i+1] for i in range(len(tps)-1)):
            return None
        if entry > 0 and sl >= entry:
            return None
    else:
        if any(tp >= sl for tp in tps) or any(tps[i] <= tps[i+1] for i in range(len(tps)-1)):
            return None
        if entry > 0 and sl <= entry:
            return None

    padded = (tps + [0.0, 0.0, 0.0])[:3]
    return ParsedSignal(symbol, side, order_kind, entry, sl, padded[0], padded[1], padded[2])


def parse_update(text: str, current: dict[str, Any]) -> Optional[tuple[str, dict[str, Any]]]:
    """Recognize simple follow-up commands for the most recent active signal."""
    upper = (text or "").upper()
    data = dict(current)
    if re.search(r"\b(CANCEL\s+(?:SIGNAL|ORDER|TRADE)|SIGNAL\s+CANCELLED|DELETE\s+PENDING)\b", upper):
        return "CANCEL", data
    if re.search(r"\b(CLOSE\s+(?:ALL|TRADE|POSITION|NOW)|EXIT\s+(?:ALL|NOW|TRADE)|CLOSE\s+NOW)\b", upper):
        return "CLOSE", data

    changed = False
    if re.search(r"\bSL\s*(?:TO|AT)?\s*(?:BE|BREAKEVEN|ENTRY)\b", upper):
        # BE is a distinct action: a market signal may not have a numeric entry in its source message.
        return "BE", data
    else:
        new_sl = extract_one(upper, [r"SL", r"STOP\s*LOSS"])
        if new_sl > 0:
            data["sl"] = new_sl
            changed = True

    new_tp = extract_labelled(upper, [r"TP", r"TAKE\s*PROFIT", r"TARGET"])
    if new_tp:
        data["tp1"] = new_tp[0]
        data["tp2"] = new_tp[1] if len(new_tp) > 1 else 0.0
        data["tp3"] = new_tp[2] if len(new_tp) > 2 else 0.0
        changed = True
    if changed:
        return "EDIT", data
    return None


def _local_tag(tag: str) -> str:
    return tag.rsplit("}", 1)[-1].lower() if "}" in tag else tag.lower()


def _clean_feed_text(value: str) -> str:
    value = re.sub(r"<script[\s\S]*?</script>|<style[\s\S]*?</style>", " ", value or "", flags=re.I)
    value = re.sub(r"<[^>]+>", " ", value)
    value = html.unescape(value)
    value = re.sub(r"\s+", " ", value)
    return value.strip()


def _child_text(entry: ET.Element, wanted: set[str]) -> str:
    values: list[str] = []
    for child in list(entry):
        if _local_tag(child.tag) in wanted:
            if _local_tag(child.tag) == "link":
                val = child.attrib.get("href") or (child.text or "")
            else:
                val = "".join(child.itertext())
            if val:
                values.append(_clean_feed_text(val))
    return " ".join(v for v in values if v)


def _feed_unix_time(entry: ET.Element) -> int:
    raw = _child_text(entry, {"pubdate", "published", "updated", "date", "created"})
    if raw:
        try:
            dt = parsedate_to_datetime(raw)
            return int(dt.timestamp())
        except (TypeError, ValueError, OverflowError):
            try:
                return int(datetime.fromisoformat(raw.replace("Z", "+00:00")).timestamp())
            except (TypeError, ValueError, OverflowError):
                pass
    return int(time.time())


def parse_rss_atom(xml_data: bytes) -> list[dict[str, Any]]:
    """Parse standard RSS 2.x or Atom entries; arbitrary HTML pages are not scraped."""
    root = ET.fromstring(xml_data)
    entries = [node for node in root.iter() if _local_tag(node.tag) in {"item", "entry"}]
    out: list[dict[str, Any]] = []
    for entry in entries:
        title = _child_text(entry, {"title"})
        body = _child_text(entry, {"description", "summary", "content", "encoded"})
        link = _child_text(entry, {"link"})
        ident = _child_text(entry, {"guid", "id"}) or link
        message = "\n".join(part for part in (title, body, link) if part).strip()
        if not message:
            continue
        if not ident:
            ident = hashlib.sha256(message.encode("utf-8")).hexdigest()
        out.append({"id": ident, "text": message[:8000], "unix_time": _feed_unix_time(entry)})
    return out


class Bridge:
    def __init__(self, cfg_path: Path):
        self.cfg_path = cfg_path
        self.cfg = load_config(cfg_path)
        self.common_files = self._resolve_common_files(self.cfg)
        self.inbox = self.common_files / "NixoBridge" / "inbox"
        self.review = self.common_files / "NixoBridge" / "review"
        self.events_log = self.common_files / "NixoBridge" / "bridge_events.csv"
        self.inbox.mkdir(parents=True, exist_ok=True)
        self.review.mkdir(parents=True, exist_ok=True)
        self.state = self._load_state()

    @staticmethod
    def _resolve_common_files(cfg: dict[str, Any]) -> Path:
        configured = os.environ.get("MT5_COMMON_FILES") or cfg.get("mt5_common_files")
        if configured:
            return Path(configured).expanduser().resolve()
        appdata = os.environ.get("APPDATA")
        if appdata:
            return Path(appdata) / "MetaQuotes" / "Terminal" / "Common" / "Files"
        raise RuntimeError("Set MT5_COMMON_FILES to the MT5 Common\\Files folder.")

    def _load_state(self) -> dict[str, Any]:
        try:
            if STATE_FILE.exists():
                return json.loads(STATE_FILE.read_text(encoding="utf-8"))
        except Exception as exc:
            log.warning("Could not read bridge state: %s", exc)
        return {"last_signal": {}, "signals": {}, "feed_seen": {}, "feed_initialized": {}}

    def _save_state(self) -> None:
        tmp = STATE_FILE.with_suffix(".tmp")
        tmp.write_text(json.dumps(self.state, ensure_ascii=False, indent=2), encoding="utf-8")
        os.replace(tmp, STATE_FILE)

    @staticmethod
    def _event_hash(value: str) -> str:
        return hashlib.sha256(value.encode("utf-8")).hexdigest()[:20]

    def write_event(self, event: dict[str, Any]) -> Path:
        fields = [
            "NIXO_SIG_V1",
            str(event["event_uid"]),
            str(event["signal_id"]),
            str(event["source_id"]),
            str(event["action"]),
            str(event["symbol"]),
            str(event["side"]),
            str(event["order_kind"]),
            f"{float(event.get('entry', 0.0)):.8f}",
            f"{float(event.get('sl', 0.0)):.8f}",
            f"{float(event.get('tp1', 0.0)):.8f}",
            f"{float(event.get('tp2', 0.0)):.8f}",
            f"{float(event.get('tp3', 0.0)):.8f}",
            str(int(event.get("unix_time", time.time()))),
        ]
        payload = "|".join(fields) + "\n"
        name = f"evt_{self._event_hash(event['event_uid'])}.sig"
        final_path = self.inbox / name
        tmp_path = final_path.with_suffix(".tmp")
        tmp_path.write_text(payload, encoding="ascii", newline="\n")
        os.replace(tmp_path, final_path)
        self._append_log(event)
        log.info("Queued %s | %s %s %s | source=%s", event["action"], event["symbol"], event["side"], event.get("entry"), event["source_id"])
        return final_path

    def _append_log(self, event: dict[str, Any]) -> None:
        import csv
        exists = self.events_log.exists()
        with self.events_log.open("a", newline="", encoding="utf-8") as f:
            w = csv.writer(f)
            if not exists:
                w.writerow(["utc_time", "event_uid", "signal_id", "source_id", "action", "symbol", "side", "kind", "entry", "sl", "tp1", "tp2", "tp3"])
            w.writerow([
                time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), event["event_uid"], event["signal_id"],
                event["source_id"], event["action"], event["symbol"], event["side"], event["order_kind"],
                event.get("entry", 0), event.get("sl", 0), event.get("tp1", 0), event.get("tp2", 0), event.get("tp3", 0),
            ])

    def _queue_signal(self, source: dict[str, Any], message_id: int, action: str, data: dict[str, Any], unix_time: int, edit_tag: str = "") -> None:
        source_id = clean_source_id(source["id"])
        signal_id = f"{source_id}:{message_id}"
        payload_hash = self._event_hash(json.dumps(data, sort_keys=True, ensure_ascii=False))
        event_uid = f"{signal_id}:{action}:{unix_time}:{edit_tag}:{payload_hash}"
        event = {
            "event_uid": event_uid,
            "signal_id": signal_id,
            "source_id": source_id,
            "action": action,
            "unix_time": unix_time,
            **data,
        }
        self.write_event(event)
        if action in ("NEW", "EDIT"):
            self.state.setdefault("signals", {})[signal_id] = data
            self.state.setdefault("last_signal", {})[source_id] = signal_id
        elif action in ("CLOSE", "CANCEL"):
            self.state.setdefault("signals", {}).pop(signal_id, None)
        self._save_state()

    def handle_message(self, source: dict[str, Any], message_id: int, text: str, unix_time: int, edited: bool = False, media_path: Optional[Path] = None) -> None:
        source_id = clean_source_id(source["id"])
        # Fail-closed control gate: no NEW/EDIT/CLOSE/CANCEL intake unless master is armed
        # and the EA heartbeat is fresh on a Demo account.
        if allow_new_intake is not None:
            ok, reason = allow_new_intake(ROOT)
            if not ok:
                log.warning("Control gate closed (%s); ignoring signal. source=%s message=%s", reason, source_id, message_id)
                return
        parsed = parse_signal(text, source)
        if parsed:
            data = parsed.to_dict()
            action = "EDIT" if edited and f"{source_id}:{message_id}" in self.state.get("signals", {}) else "NEW"
            # If a new message is a fresh setup, never treat it as an edit to a prior message.
            self._queue_signal(source, message_id, action, data, unix_time, "edited" if edited else "new")
            return

        signal_id = self.state.get("last_signal", {}).get(source_id)
        current = self.state.get("signals", {}).get(signal_id) if signal_id else None
        if current:
            update = parse_update(text, current)
            if update:
                action, data = update
                msgid = int(signal_id.rsplit(":", 1)[-1])
                self._queue_signal(source, msgid, action, data, unix_time, f"update_{message_id}")
                return

        if media_path:
            note = media_path.with_suffix(".txt")
            note.write_text(
                f"source={source_id}\nmessage_id={message_id}\nreceived_utc={unix_time}\n"
                "status=MANUAL_REVIEW_REQUIRED\nNo automatic order is created from screenshots in bridge v0.2.\n",
                encoding="utf-8",
            )
            log.info("Screenshot saved for manual review: %s", media_path)
        elif text and re.search(r"\b(BUY|SELL|LONG|SHORT)\b", text, re.I):
            log.warning("Unparsed/ambiguous possible signal; ignored (no SL/TP or unsupported format). source=%s message=%s", source_id, message_id)

    def _fetch_rss_source(self, source: dict[str, Any]) -> list[dict[str, Any]]:
        url = str(source.get("feed_url", "")).strip()
        if not url.startswith(("https://", "http://")):
            raise ValueError("RSS/Atom feed URL must start with http:// or https://")
        req = urllib.request.Request(url, headers={"User-Agent": "NixoSignalBridge/0.2 (+RSS reader)"})
        timeout = max(5, int(os.environ.get("NIXO_RSS_TIMEOUT_SECONDS", "15")))
        with urllib.request.urlopen(req, timeout=timeout) as response:
            data = response.read(2_000_000)
        return parse_rss_atom(data)

    async def run_rss_sources(self, sources: list[dict[str, Any]]) -> None:
        interval = max(15, int(os.environ.get("NIXO_RSS_POLL_SECONDS", "45")))
        seen_map = self.state.setdefault("feed_seen", {})
        initialized = self.state.setdefault("feed_initialized", {})
        # On first start, baseline existing entries to avoid executing old/stale signals.
        # A failed baseline remains pending; it must never turn into a backfill on the next poll.
        for src in sources:
            sid = clean_source_id(src["id"])
            if initialized.get(sid) or sid in seen_map:
                initialized[sid] = True
                continue
            try:
                entries = await asyncio.to_thread(self._fetch_rss_source, src)
                keys = [str(item["id"]) for item in entries]
                seen_map[sid] = keys
                initialized[sid] = True
                self._save_state()
                log.info("RSS baseline loaded: %s | %d existing entries marked as seen (no backfill)", src.get("name", sid), len(keys))
            except Exception as exc:
                log.error("RSS initial read failed for %s: %s; baseline will retry before processing any feed item", src.get("name", sid), exc)

        while True:
            for src in sources:
                sid = clean_source_id(src["id"])
                seen = set(str(x) for x in seen_map.get(sid, []))
                try:
                    entries = await asyncio.to_thread(self._fetch_rss_source, src)
                    if not initialized.get(sid, False):
                        seen_map[sid] = [str(item["id"]) for item in entries]
                        initialized[sid] = True
                        self._save_state()
                        log.info("RSS baseline completed after retry: %s | %d items marked seen (no backfill)", src.get("name", sid), len(entries))
                        continue
                    fresh = [item for item in entries if str(item["id"]) not in seen]
                    # Sort by published timestamp to process the oldest new entry first.
                    fresh.sort(key=lambda item: int(item.get("unix_time", 0)))
                    for item in fresh:
                        synthetic_id = int(hashlib.sha256(str(item["id"]).encode("utf-8")).hexdigest()[:12], 16)
                        self.handle_message(src, synthetic_id, item["text"], int(item["unix_time"]))
                        seen.add(str(item["id"]))
                    if fresh:
                        seen_map[sid] = list(seen)[-500:]
                        self._save_state()
                        log.info("RSS source %s: %d new entries checked", src.get("name", sid), len(fresh))
                except (urllib.error.URLError, TimeoutError, ValueError, ET.ParseError) as exc:
                    log.warning("RSS poll failed for %s: %s", src.get("name", sid), exc)
                except Exception as exc:
                    log.exception("Unexpected RSS error for %s: %s", src.get("name", sid), exc)
            await asyncio.sleep(interval)

    async def run(self) -> None:
        load_local_env()
        enabled = [s for s in self.cfg["sources"] if s.get("enabled")]
        telegram_sources = [s for s in enabled if str(s.get("source_type", "telegram")).lower() != "rss"]
        rss_sources = [s for s in enabled if str(s.get("source_type", "telegram")).lower() == "rss"]
        if not enabled:
            log.warning("No enabled sources in config/sources.json. Add a Telegram channel or RSS/Atom feed and restart.")
            return

        tasks: list[asyncio.Task[Any]] = []
        client = None
        if telegram_sources:
            api_id = os.environ.get("TELEGRAM_API_ID") or str(self.cfg.get("telegram_api_id", "")).strip()
            api_hash = os.environ.get("TELEGRAM_API_HASH", "").strip()
            if not api_id or not api_hash:
                log.error("Telegram sources are enabled, but TELEGRAM_API_ID / TELEGRAM_API_HASH are not configured. RSS sources can still run.")
            else:
                try:
                    from telethon import TelegramClient, events
                    session = ROOT / self.cfg.get("session_name", "nixo_telegram")
                    client = TelegramClient(str(session), int(api_id), api_hash)
                    await client.start()
                    for source in telegram_sources:
                        channel = str(source.get("channel", "")).strip().lstrip("@")
                        if not channel:
                            log.warning("Skipping Telegram source with missing channel: %s", source.get("id"))
                            continue
                        try:
                            entity = await client.get_entity(channel)
                        except Exception as exc:
                            log.error("Cannot access @%s (%s): %s", channel, source.get("id"), exc)
                            continue

                        async def on_new(event, src=source):
                            msg = event.message
                            text = msg.message or ""
                            media_path = None
                            if msg.photo:
                                try:
                                    review_dir = self.review / clean_source_id(src["id"])
                                    review_dir.mkdir(parents=True, exist_ok=True)
                                    media_path = Path(await msg.download_media(file=str(review_dir / f"{msg.id}")))
                                except Exception as exc:
                                    log.warning("Could not download screenshot: %s", exc)
                            self.handle_message(src, msg.id, text, int(msg.date.timestamp()), False, media_path)

                        async def on_edit(event, src=source):
                            msg = event.message
                            text = msg.message or ""
                            media_path = None
                            if msg.photo:
                                try:
                                    review_dir = self.review / clean_source_id(src["id"])
                                    review_dir.mkdir(parents=True, exist_ok=True)
                                    media_path = Path(await msg.download_media(file=str(review_dir / f"{msg.id}_edited")))
                                except Exception as exc:
                                    log.warning("Could not download edited screenshot: %s", exc)
                            self.handle_message(src, msg.id, text, int(msg.edit_date.timestamp() if msg.edit_date else msg.date.timestamp()), True, media_path)

                        client.add_event_handler(on_new, events.NewMessage(chats=entity, incoming=True))
                        client.add_event_handler(on_edit, events.MessageEdited(chats=entity, incoming=True))
                        log.info("Listening Telegram: %s (@%s) | parser=%s", source.get("name", source["id"]), channel, source.get("parser", "standard"))
                    tasks.append(asyncio.create_task(client.run_until_disconnected()))
                except ImportError:
                    log.error("Telegram sources enabled but Telethon is missing. Install bridge/requirements.txt.")
                except Exception as exc:
                    log.exception("Telegram startup failed: %s", exc)

        if rss_sources:
            tasks.append(asyncio.create_task(self.run_rss_sources(rss_sources)))
            log.info("RSS/Atom sources enabled: %d", len(rss_sources))
        if not tasks:
            raise RuntimeError("No signal source could start. Check Telegram credentials and RSS feed URLs.")
        log.info("Nixo Signal Bridge %s active. It only parses and queues signals; MT5 controls paper/live behavior.", VERSION)
        try:
            await asyncio.gather(*tasks)
        finally:
            if client is not None:
                await client.disconnect()


def self_test() -> int:
    source = {"id": "test", "allowed_symbols": ["XAUUSD"], "assume_single_symbol": False}
    cases = [
        ("BUY XAUUSD NOW\nSL: 4040\nTP1: 4060\nTP2: 4070\nTP3: 4080", "BUY", "MARKET", 4060.0, 4070.0, 4080.0),
        ("SELL GOLD LIMIT\nENTRY: 4050-4052\nSL: 4060\nTP: 4040", "SELL", "LIMIT", 4040.0, 0.0, 0.0),
        ("BUY XAUUSD LIMIT 4060-4062\nSL 4050\nTP1 4070", "BUY", "LIMIT", 4070.0, 0.0, 0.0),
        ("SELL GOLD STOP 4050\nSL 4060\nTP1 4040", "SELL", "STOP", 4040.0, 0.0, 0.0),
        ("BUY XAUUSD\nENTRY 4060\nSL 4050\nTP1 4070", "BUY", "LIMIT", 4070.0, 0.0, 0.0),
        ("SELL XAUUSD NOW\nSL 4070\nTP1 4050\nTP2 4040", "SELL", "MARKET", 4050.0, 4040.0, 0.0),
        ("BUY GOLD NOW\nSL 2400\nTP1 2410", "BUY", "MARKET", 2410.0, 0.0, 0.0),
        ("BUY XAUUSD @ 4060\nSL 4050\nTP1 4070", "BUY", "LIMIT", 4070.0, 0.0, 0.0),
    ]
    for text, side, kind, tp1, tp2, tp3 in cases:
        p = parse_signal(text, source)
        if p is None or p.side != side or p.order_kind != kind:
            print("FAIL:", text, p)
            return 1
        got = (p.tp1, p.tp2, p.tp3)
        exp = (tp1, tp2, tp3)
        if any(abs(a-b) > 1e-6 for a,b in zip(got,exp)):
            print("FAIL TP:", text, p, "expected", exp)
            return 1
    gold_source = {"id":"gold_alias", "allowed_symbols":["GOLD"]}
    gold = parse_signal("BUY GOLD NOW\nSL 2400\nTP1 2410", gold_source)
    if gold is None or gold.symbol != "XAUUSD":
        print("FAIL: GOLD alias allow-list", gold)
        return 1
    current = {"symbol":"XAUUSD", "side":"BUY", "order_kind":"MARKET", "entry":0.0, "sl":4040.0, "tp1":4060.0, "tp2":0.0, "tp3":0.0}
    be = parse_update("SL TO BE", current)
    if not be or be[0] != "BE":
        print("FAIL: BE follow-up", be)
        return 1
    edit = parse_update("SL: 4052 TP1: 4070 TP2: 4080", current)
    if not edit or edit[0] != "EDIT" or edit[1]["sl"] != 4052.0 or edit[1]["tp2"] != 4080.0:
        print("FAIL: numeric update", edit)
        return 1
    close = parse_update("CLOSE TRADE", current)
    if not close or close[0] != "CLOSE":
        print("FAIL: close update", close)
        return 1
    cancel = parse_update("CANCEL SIGNAL", current)
    if not cancel or cancel[0] != "CANCEL":
        print("FAIL: cancel update", cancel)
        return 1
    sample_feed = b'''<?xml version="1.0"?><rss version="2.0"><channel><item><title>BUY XAUUSD NOW SL 4040 TP1 4060</title><guid>abc-1</guid><description>TP2 4070 TP3 4080</description><pubDate>Thu, 05 Nov 2026 10:00:00 GMT</pubDate></item></channel></rss>'''
    feed_entries = parse_rss_atom(sample_feed)
    if len(feed_entries) != 1 or "BUY XAUUSD" not in feed_entries[0]["text"]:
        print("FAIL: RSS entry parser", feed_entries)
        return 1
    feed_signal = parse_signal(feed_entries[0]["text"], source)
    if feed_signal is None or (feed_signal.tp1, feed_signal.tp2, feed_signal.tp3) != (4060.0, 4070.0, 4080.0):
        print("FAIL: RSS-to-signal parsing", feed_signal)
        return 1
    print("PASS: signal templates, GOLD alias, BE/SL/TP/CLOSE/CANCEL, RSS parser and RSS-to-signal tests")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=APP_NAME)
    ap.add_argument("--config", type=Path, default=DEFAULT_CONFIG)
    ap.add_argument("--self-test", action="store_true")
    args = ap.parse_args()
    if args.self_test:
        return self_test()
    bridge = Bridge(args.config)
    asyncio.run(bridge.run())
    return 0

if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        log.info("Stopped by user.")
    except Exception as exc:
        log.error("Bridge stopped: %s", exc)
        raise
