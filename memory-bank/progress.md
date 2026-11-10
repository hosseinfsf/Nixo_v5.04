# Progress

**What works**

- Control Center alpha has Demo-gated ON/OFF, an EA/Bridge status display, and Telegram source CRUD.
- EA and Bridge share a Common Files control/status protocol; OFF discards new queued events without touching managed trades/orders.
- Control protocol tests and the existing signal parser self-test pass.

**Not started / backlog**

- Compile and verify the MQ5 changes in MetaEditor and run an end-to-end Demo test.
- GUI Telegram first-login flow, EA installer/updater, richer channel metrics, EXE packaging, and multi-day soak test.

**Known issues**

- New MQ5 source has not been compiled because MetaEditor is unavailable here.
- First-time Telethon authorization may open a console; the running EA must be recompiled before the UI can enable the system.

_Keep bullets factual and small; link issues or PRs when useful._
