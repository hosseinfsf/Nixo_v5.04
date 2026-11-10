# System patterns

- **High-level layout**: `control_center/` owns the Windows UI; `bridge/` reads Telegram and writes signal events; the MQ5 EA consumes events and manages trades.
- **Data flow**: Control Center atomically writes `Common/Files/NixoBridge/control.json`; EA publishes `ea_status.json`; Bridge publishes `bridge_status.json` and writes `inbox/*.sig`.
- **Patterns to follow**: Atomic JSON replacement, explicit heartbeat freshness, Demo validation in both EA and Bridge, reject malformed control state, keep OFF limited to new external signal intake.
- **Patterns to avoid**: Closing positions/deleting orders on OFF, trusting UI-only account checks, committing Telegram credentials or session files.

_Link to key files or packages when it saves repetition._
