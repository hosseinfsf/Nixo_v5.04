# -*- coding: utf-8 -*-
"""
پارس سیگنال با Groq (رایگان و بسیار سریع)
"""

import os
import json
import logging
from typing import Optional
from ..models import Signal

log = logging.getLogger("GroqParser")

try:
    from groq import Groq
    GROQ_AVAILABLE = True
except ImportError:
    GROQ_AVAILABLE = False


SYSTEM_PROMPT = """You are a precise trading signal extractor for forex and gold.
Extract a trading signal from the text if it clearly exists.
Return ONLY valid JSON with these fields (use null if missing):
{
  "side": "BUY" or "SELL",
  "symbol": "XAUUSD" or standard symbol,
  "entry": number,
  "sl": number or null,
  "tp1": number or null,
  "tp2": number or null,
  "tp3": number or null,
  "confidence": number between 0 and 1
}
Rules:
- Only extract if direction + symbol + entry price are clearly present.
- Normalize gold related words to XAUUSD.
- If no clear signal, return {"side": null}.
- Be strict and accurate.
"""


def parse_signal_with_groq(text: str) -> Optional[Signal]:
    if not GROQ_AVAILABLE:
        log.warning("کتابخانه groq نصب نیست")
        return None

    api_key = os.getenv("GROQ_API_KEY", "").strip()
    if not api_key:
        log.warning("GROQ_API_KEY تنظیم نشده")
        return None

    try:
        client = Groq(api_key=api_key)

        response = client.chat.completions.create(
            model="llama-3.1-8b-instant",
            messages=[
                {"role": "system", "content": SYSTEM_PROMPT},
                {"role": "user", "content": text[:1500]}
            ],
            temperature=0.05,
            max_tokens=350,
            response_format={"type": "json_object"}
        )

        content = response.choices[0].message.content
        data = json.loads(content)

        if not data.get("side") or data["side"] not in ("BUY", "SELL"):
            return None

        symbol = str(data.get("symbol", "")).upper()
        if not symbol:
            return None

        if symbol in ("GOLD", "XAU", "GOLDUSD", "XAUUSD"):
            symbol = "XAUUSD"

        entry = data.get("entry")
        if entry is None:
            return None

        def to_float(v):
            try:
                return float(v) if v is not None else None
            except (TypeError, ValueError):
                return None

        return Signal(
            side=data["side"].upper(),
            symbol=symbol,
            entry=float(entry),
            sl=to_float(data.get("sl")),
            tp1=to_float(data.get("tp1")),
            tp2=to_float(data.get("tp2")),
            tp3=to_float(data.get("tp3")),
            raw_text=text[:400],
            confidence=float(data.get("confidence", 0.75)),
            parser="ai-groq"
        )

    except Exception as e:
        log.error(f"Groq error: {e}")
        return None
