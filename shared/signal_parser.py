# -*- coding: utf-8 -*-
"""
لایه مشترک پارس سیگنال (Rule-based + AI)
قابل استفاده برای X، تلگرام، تریدینگ‌ویو و منابع دیگر
"""

import re
import logging
from typing import Optional, List
from .models import Signal

log = logging.getLogger("SignalParser")

# ------------------------------------------------------------------
# الگوهای قوی Rule-based
# ------------------------------------------------------------------
BUY_PATTERN  = re.compile(
    r"(?i)\b(buy|long|خرید|خرید\s*کن(?:ید)?|بای|خرید\s*کنید|going\s*long)\b"
)
SELL_PATTERN = re.compile(
    r"(?i)\b(sell|short|فروش|فروش\s*کن(?:ید)?|سل|فروش\s*کنید|going\s*short)\b"
)

SYMBOL_MAP = {
    "XAUUSD": ["xauusd", "xau", "gold", "goldusd", "طلا", "اونس", "xau/usd"],
    "EURUSD": ["eurusd", "eur", "eur/usd"],
    "GBPUSD": ["gbpusd", "gbp", "gbp/usd"],
    "USDJPY": ["usdjpy", "jpy", "usd/jpy"],
    "USDCHF": ["usdchf", "chf"],
    "AUDUSD": ["audusd", "aud"],
    "USDCAD": ["usdcad", "cad"],
    "NZDUSD": ["nzdusd", "nzd"],
    "BTCUSD": ["btcusd", "btc", "bitcoin", "btc/usd"],
    "ETHUSD": ["ethusd", "eth", "ethereum", "eth/usd"],
}

ENTRY_PATTERNS = [
    re.compile(r"(?i)(?:entry|enter|ورود|نقطه\s*ورود|entry\s*price|at|@)\s*[:=]?\s*([\d]{3,6}(?:\.\d{1,3})?)"),
    re.compile(r"(?i)(?:price|قیمت)\s*[:=]?\s*([\d]{3,6}(?:\.\d{1,3})?)"),
    re.compile(r"(?i)\b([\d]{4}(?:\.\d{1,2})?)\b"),  # عدد ۴ رقمی رایج طلا
]

SL_PATTERNS = [
    re.compile(r"(?i)(?:sl|s\.l|stop|stop\s*loss|حد\s*ضرر|استاپ|stop\s*loss)\s*[:=]?\s*([\d]{3,6}(?:\.\d{1,3})?)"),
]

TP_PATTERNS = [
    re.compile(r"(?i)(?:tp\s*1|tp1|target\s*1|هدف\s*۱|هدف\s*1|t1)\s*[:=]?\s*([\d]{3,6}(?:\.\d{1,3})?)"),
    re.compile(r"(?i)(?:tp\s*2|tp2|target\s*2|هدف\s*۲|هدف\s*2|t2)\s*[:=]?\s*([\d]{3,6}(?:\.\d{1,3})?)"),
    re.compile(r"(?i)(?:tp\s*3|tp3|target\s*3|هدف\s*۳|هدف\s*3|t3)\s*[:=]?\s*([\d]{3,6}(?:\.\d{1,3})?)"),
    re.compile(r"(?i)(?:tp|target|هدف)\s*[:=]?\s*([\d]{3,6}(?:\.\d{1,3})?)"),
]


def _extract_number(patterns: List[re.Pattern], text: str) -> Optional[float]:
    for pat in patterns:
        m = pat.search(text)
        if m:
            try:
                val = float(m.group(1))
                if 50 < val < 500000:
                    return val
            except (ValueError, IndexError):
                continue
    return None


def parse_rule_based(text: str, allowed_symbols: List[str] = None, source: str = "unknown") -> Optional[Signal]:
    if not text or len(text.strip()) < 5:
        return None

    text_clean = text.strip()

    # جهت
    side = None
    if BUY_PATTERN.search(text_clean):
        side = "BUY"
    elif SELL_PATTERN.search(text_clean):
        side = "SELL"
    if not side:
        return None

    # نماد
    symbol = None
    for std, aliases in SYMBOL_MAP.items():
        for alias in aliases + [std.lower()]:
            if re.search(rf"\b{re.escape(alias)}\b", text_clean, re.IGNORECASE):
                symbol = std
                break
        if symbol:
            break

    if not symbol:
        return None

    if allowed_symbols and symbol.upper() not in [s.upper() for s in allowed_symbols]:
        return None

    # Entry (اجباری طبق نیاز کاربر)
    entry = _extract_number(ENTRY_PATTERNS, text_clean)
    if entry is None:
        return None

    sl  = _extract_number(SL_PATTERNS, text_clean)
    tp1 = _extract_number([TP_PATTERNS[0]], text_clean)
    tp2 = _extract_number([TP_PATTERNS[1]], text_clean)
    tp3 = _extract_number([TP_PATTERNS[2]], text_clean)

    if tp1 is None:
        tp1 = _extract_number([TP_PATTERNS[3]], text_clean)

    return Signal(
        side=side,
        symbol=symbol,
        entry=entry,
        sl=sl,
        tp1=tp1,
        tp2=tp2,
        tp3=tp3,
        source=source,
        raw_text=text_clean[:400],
        confidence=0.88,
        parser="rule"
    )


def parse_with_ai(text: str, source: str = "unknown", provider: str = "groq") -> Optional[Signal]:
    try:
        if provider == "groq":
            from .ai_providers.groq_free import parse_signal_with_groq
            result = parse_signal_with_groq(text)
            if result:
                result.source = source
                result.parser = "ai-groq"
                return result
    except Exception as e:
        log.warning(f"AI parser error: {e}")
    return None


def parse_signal(
    text: str,
    source: str = "unknown",
    allowed_symbols: List[str] = None,
    use_ai_fallback: bool = True,
    ai_provider: str = "groq"
) -> Optional[Signal]:
    """
    تابع اصلی برای همه منابع.
    اول Rule-based، در صورت نیاز AI.
    """
    signal = parse_rule_based(text, allowed_symbols, source)
    if signal and signal.is_valid():
        return signal

    if use_ai_fallback:
        signal = parse_with_ai(text, source, ai_provider)
        if signal and signal.is_valid():
            if allowed_symbols and signal.symbol.upper() not in [s.upper() for s in allowed_symbols]:
                return None
            return signal

    return None
