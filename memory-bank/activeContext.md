# Active context

Telegram → MT5 Control Center scaffold complete; EA safety and bridge fixes applied.

Implemented:
- control_center/control_center.py — Tkinter: master ON/OFF (writes control.json master_armed), per-source enable/disable (writes sources.json), health (ea_status heartbeat + trade_mode), Telegram login wizard (Telethon session), source add/manage wizard.
- control_center/source_wizard.py — add / edit / toggle / remove sources in config/sources.json.
- control_center/start_control_center.bat — venv + bridge requirements (Telethon) launcher.
- bridge/signal_bridge.py — control gate via shared.control_protocol.allow_new_intake (fail-closed), RSS synthetic_id changed to 12-hex, control_protocol import added.
- mt5 EA — SEEN dedup fixed (event_uid = signalId only, not +timestamp); ControlGateAllowsLive() added (master armed + fresh ea_status heartbeat + ACCOUNT_TRADE_MODE_DEMO enforced before SignalExecuteLive).

Priority path: Telegram channels only (RSS kept; X/TV deferred).
One Telethon session; many channels; each source_id tracked separately.

Next: EA EDIT validation, DEMO_SAFE_CHECKLIST + README update.
