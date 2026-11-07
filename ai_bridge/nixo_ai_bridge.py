#!/usr/bin/env python3
"""Nixo AI Advisory Bridge.

Reads a market snapshot exported by the EA, requests an advisory classification
from an OpenAI-compatible chat-completions endpoint, and writes a heartbeat/status
file for the dashboard. This helper is advisory-only and never sends orders.
"""
from __future__ import annotations

import json
import logging
import os
import re
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parent
ENV_FILE = ROOT / ".env.local"
LOG_FILE = ROOT / "nixo_ai_bridge.log"
POLL_SECONDS = 3

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)s | %(message)s",
    handlers=[logging.StreamHandler(sys.stdout), logging.FileHandler(LOG_FILE, encoding="utf-8")],
)
log = logging.getLogger("nixo_ai_bridge")


def load_local_env() -> None:
    if not ENV_FILE.exists():
        return
    for raw in ENV_FILE.read_text(encoding="utf-8-sig").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        value = value.strip().strip('"').strip("'")
        if key.strip() and value:
            os.environ.setdefault(key.strip(), value)


def common_files_dir() -> Path:
    configured = os.environ.get("MT5_COMMON_FILES", "").strip()
    if configured:
        return Path(configured).expanduser().resolve()
    appdata = os.environ.get("APPDATA", "").strip()
    if appdata:
        return Path(appdata) / "MetaQuotes" / "Terminal" / "Common" / "Files"
    raise RuntimeError("Set MT5_COMMON_FILES in ai_bridge/.env.local")


def clean_field(value: Any, limit: int = 112) -> str:
    text = re.sub(r"[|\r\n]+", " ", str(value or "")).strip()
    text = re.sub(r"\s+", " ", text)
    return text[:limit] or "No advisory summary"


def status_path(common: Path) -> Path:
    folder = common / "NixoBridge"
    folder.mkdir(parents=True, exist_ok=True)
    return folder / "ai_status.txt"


def write_status(common: Path, state: str, bias: str, risk: str, summary: str) -> None:
    payload = "|".join([
        state.upper(), str(int(time.time())), clean_field(bias, 16).upper(),
        clean_field(risk, 16).upper(), clean_field(summary, 112),
    ]) + "\n"
    target = status_path(common)
    tmp = target.with_suffix(".tmp")
    tmp.write_text(payload, encoding="ascii", errors="replace")
    os.replace(tmp, target)


def read_snapshot(common: Path) -> tuple[str, list[str]] | None:
    path = common / "NixoBridge" / "ai_market_snapshot.csv"
    if not path.exists():
        return None
    try:
        raw = path.read_text(encoding="utf-8", errors="replace").strip().splitlines()
        if not raw:
            return None
        line = raw[-1].strip()
        fields = line.split("|")
        if len(fields) < 12:
            return None
        return line, fields
    except OSError as exc:
        log.warning("Snapshot read failed: %s", exc)
        return None


def request_advisory(fields: list[str]) -> dict[str, str]:
    base_url = os.environ.get("NIXO_AI_BASE_URL", "https://api.openai.com/v1/chat/completions").strip()
    model = os.environ.get("NIXO_AI_MODEL", "").strip()
    api_key = os.environ.get("NIXO_AI_API_KEY", "").strip()
    if not model or not api_key:
        raise RuntimeError("Configure NIXO_AI_MODEL and NIXO_AI_API_KEY in ai_bridge/.env.local")

    (stamp, symbol, timeframe, bid, ask, spread, atr, rsi, adx,
     strategy, running, manual) = fields[:12]
    market = {
        "time_utc": stamp, "symbol": symbol, "timeframe": timeframe,
        "bid": bid, "ask": ask, "spread_points": spread, "atr": atr,
        "rsi": rsi, "adx": adx, "strategy": strategy,
        "automation_running": running == "1", "manual_mode": manual == "1",
    }
    system_prompt = (
        "You are the read-only market advisory module for the Nixo trading dashboard. "
        "Do not place trades, recommend an exact entry, invent missing context, or promise profit. "
        "Assess only the supplied snapshot and state uncertainty. Return one compact JSON object only, "
        'with keys bias (BULLISH, BEARISH, or NEUTRAL), risk (LOW, MEDIUM, or HIGH), and summary '
        "(plain text, at most 100 characters). If data is insufficient, use NEUTRAL and HIGH."
    )
    body = {
        "model": model,
        "temperature": 0.1,
        "messages": [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": json.dumps(market, ensure_ascii=False)},
        ],
    }
    request = urllib.request.Request(
        base_url,
        data=json.dumps(body).encode("utf-8"),
        headers={"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"},
        method="POST",
    )
    timeout = max(5, int(os.environ.get("NIXO_AI_TIMEOUT_SECONDS", "25")))
    with urllib.request.urlopen(request, timeout=timeout) as response:
        result = json.loads(response.read().decode("utf-8"))
    content = result["choices"][0]["message"]["content"]
    if isinstance(content, list):
        content = "".join(str(part.get("text", "")) for part in content if isinstance(part, dict))
    content = str(content).strip()
    content = re.sub(r"^```(?:json)?\s*|\s*```$", "", content, flags=re.I)
    parsed = json.loads(content)

    bias = str(parsed.get("bias", "NEUTRAL")).upper()
    risk = str(parsed.get("risk", "HIGH")).upper()
    if bias not in {"BULLISH", "BEARISH", "NEUTRAL"}:
        bias = "NEUTRAL"
    if risk not in {"LOW", "MEDIUM", "HIGH"}:
        risk = "HIGH"
    return {"bias": bias, "risk": risk, "summary": clean_field(parsed.get("summary", "Insufficient context"), 112)}


def main() -> int:
    load_local_env()
    common = common_files_dir()
    target = status_path(common)
    log.info("Nixo AI Advisory Bridge started. MT5 Common Files: %s", common)
    last_snapshot = ""
    last_advisory = {"bias": "WAIT", "risk": "—", "summary": "Waiting for first market snapshot"}
    last_request_at = 0.0
    refresh = max(10, int(os.environ.get("NIXO_AI_REFRESH_SECONDS", "30")))

    while True:
        snap = read_snapshot(common)
        now = time.time()
        if snap and snap[0] != last_snapshot and now - last_request_at >= refresh:
            last_snapshot = snap[0]
            last_request_at = now
            try:
                last_advisory = request_advisory(snap[1])
                log.info("AI advisory | %s | risk=%s | %s", last_advisory["bias"], last_advisory["risk"], last_advisory["summary"])
                write_status(common, "ONLINE", last_advisory["bias"], last_advisory["risk"], last_advisory["summary"])
            except (urllib.error.URLError, TimeoutError, json.JSONDecodeError, KeyError, RuntimeError, ValueError) as exc:
                last_advisory = {"bias": "WAIT", "risk": "HIGH", "summary": clean_field(f"AI unavailable: {exc}", 112)}
                log.error("AI request failed: %s", exc)
                write_status(common, "ERROR", last_advisory["bias"], last_advisory["risk"], last_advisory["summary"])
            except Exception as exc:  # Keep heartbeat alive on provider-specific errors.
                last_advisory = {"bias": "WAIT", "risk": "HIGH", "summary": clean_field(f"AI error: {exc}", 112)}
                log.exception("Unexpected AI error")
                write_status(common, "ERROR", last_advisory["bias"], last_advisory["risk"], last_advisory["summary"])
        elif snap:
            # Refresh timestamp so Nixo can distinguish an active helper from a stale process.
            state = "ONLINE" if last_advisory["bias"] != "WAIT" else "ERROR"
            write_status(common, state, last_advisory["bias"], last_advisory["risk"], last_advisory["summary"])
        else:
            write_status(common, "OFFLINE", "WAIT", "HIGH", "Waiting for Nixo market snapshot")
        time.sleep(POLL_SECONDS)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        log.info("Stopped by user")
