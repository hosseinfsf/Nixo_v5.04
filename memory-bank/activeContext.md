# Active context

**Current focus**: Building the first Nixo Control Center slice against the checked-out v5.05 sources. Priority is a fail-closed, Demo-only control protocol; OFF must block/drop incoming signal events without pausing EA position management or changing existing trades/orders.

**In progress**:

- [x] Inspected the active Telegram bridge, signal inbox, and EA lifecycle.
- [x] Implemented the shared-file control/status protocol, Demo gates, and initial Tkinter UI/source manager.
- [ ] Finish focused validation and document the new launch flow.

**Decisions (recent)**:

- Reuse Python/Tkinter and MT5 Common Files for the initial Windows-only prototype.
- Keep legacy behavior when no `control.json` exists; once Control Center creates one, malformed/missing state fails closed.
- Demo account confirmation must come from a fresh EA heartbeat; the EA also enforces Demo-only independently.

**Open questions**:

- Installer/updater, first-time GUI Telegram login, advanced source metrics, packaging, and long-duration Demo soak test remain later phases.

_Update when the task or branch focus changes._
