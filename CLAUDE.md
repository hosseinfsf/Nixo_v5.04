# Nixo — Agent notes

## Product
Demo-first Telegram → MT5 signal copy. Control Center owns master ON/OFF.
Bridge parses Telegram and writes `NIXO_SIG_V1` files. EA places Demo orders
and manages open trades. OFF stops NEW intake only.

## Layout
- `mt5/Nixo_v5.04_TradingModes_AdvancedAnalytics.mq5` — primary EA
- `bridge/signal_bridge.py` — Telegram/RSS → inbox
- `control_center/` — Tkinter setup + ON/OFF + source manager
- `shared/control_protocol.py` — control.json / ea_status helpers
- `config/sources.json` — Telegram channels
- `memory-bank/` — active context and progress
- `docs/DEMO_SAFE_CHECKLIST.md` — soak-test checklist

## Safety
- EA enforces `ACCOUNT_TRADE_MODE_DEMO` before any external live order.
- Fail closed: missing/malformed control.json or stale ea_status → no NEW.
- Never commit `.env.local`, `*.session`, API hash/tokens.
- Do not hand-edit `.ex5`; compile from `.mq5` only.

## Defaults
- Startup trading mode: EXTERNAL
- Master armed: OFF until Control Center ON
- Per-source enable in sources.json; roulette state keyed by source_id

## Verify
- `pytest` for parsers/protocol
- `py -3 bridge/signal_bridge.py --self-test`
- MQL5 compile only inside MetaEditor (F7)
