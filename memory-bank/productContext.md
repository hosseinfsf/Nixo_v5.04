# Product context

- **Problem**: Nixo currently requires separate MT5, Python bridge, and source-management steps.
- **Primary users**: The local Windows MT5 operator.
- **UX principles**: One visible system state and ON/OFF action; fail closed when EA/MT5 status is stale or the account is not Demo; no surprise changes to existing trades.
- **Constraints**: Local-only Telegram credentials/session; no remote control endpoint; initial app uses Python/Tkinter and MT5 Common Files.
