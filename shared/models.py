# -*- coding: utf-8 -*-
"""
مدل استاندارد سیگنال برای تمام منابع Nixo
"""

from dataclasses import dataclass, asdict, field
from typing import Optional
from datetime import datetime, timezone
import json


@dataclass
class Signal:
    side: str                          # BUY یا SELL
    symbol: str                        # مثلا XAUUSD
    entry: Optional[float] = None
    sl: Optional[float] = None
    tp1: Optional[float] = None
    tp2: Optional[float] = None
    tp3: Optional[float] = None
    source: str = "unknown"
    raw_text: str = ""
    confidence: float = 0.0
    parser: str = "rule"
    received_at: str = field(default_factory=lambda: datetime.now(timezone.utc).isoformat())

    def is_valid(self) -> bool:
        if self.side not in ("BUY", "SELL"):
            return False
        if not self.symbol:
            return False
        if self.entry is None or self.entry <= 0:
            return False
        return True

    def to_nixo_json(self) -> str:
        payload = {
            "version": "NIXO_SIG_V1",
            "source": self.source,
            "side": self.side,
            "symbol": self.symbol,
            "entry": self.entry,
            "sl": self.sl,
            "tp1": self.tp1,
            "tp2": self.tp2,
            "tp3": self.tp3,
            "raw_text": self.raw_text[:500],
            "confidence": self.confidence,
            "parser": self.parser,
            "received_at": self.received_at
        }
        return json.dumps(payload, ensure_ascii=False, indent=2)
