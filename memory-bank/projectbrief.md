# Project brief

- **Goal**: Provide a Windows Control Center for Nixo's Telegram bridge and MT5 EA, with independently enforced Demo-only signal intake.
- **Non-goals for the current slice**: Automatic EA installation/compilation, EXE packaging, first-time Telegram login UI, multi-day soak testing, and live-account trading.
- **Success criteria**: ON requires a fresh EA heartbeat confirming Demo and EXTERNAL; OFF blocks and discards new queued signal events while leaving existing positions, pending orders, SL/TP, and EA managers unchanged.

_Update this when scope changes. Paths in this memory bank: `./memory-bank/`._
