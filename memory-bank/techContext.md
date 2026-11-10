# Tech context

**Stack**

- Language / runtime: Python 3.10+ and MQL5.
- Framework: Tkinter (stdlib); MetaTrader 5 EA.
- Major dependencies: Telethon in the existing Telegram bridge.

**Environment**

- Windows desktop with MetaTrader 5.
- `MT5_COMMON_FILES` may override the Common Files path; Telegram credentials stay in `bridge/.env.local`.

**Build & test**

- `.\.venv\Scripts\python.exe -m unittest discover -s bridge -p test_control_protocol.py`
- `.\.venv\Scripts\python.exe bridge\signal_bridge.py --self-test`
- Compile MQ5 in MetaEditor; MetaEditor is not installed in the current environment.

**Constraints**

- First Control Center prototype is source-run Python; EXE packaging and installer automation are later milestones.
