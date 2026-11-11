"""Nixo Control Center — the single window that runs the whole signal stack."""
from __future__ import annotations

import tkinter as tk
from tkinter import messagebox, ttk

from . import paths, status, theme
from .activity import ActivityLog
from .cards import CheckRow, StatusCard
from .installer_dialog import InstallerDialog
from .processes import ProcessManager
from .setup_dialog import SetupDialog
from .setup_state import TELEGRAM_SESSION
from .source_manager import SourceManager

REFRESH_MS = 2000
WINDOW_MIN = (860, 700)


class ControlCenter:
    """Owns the window, the helper processes, and the control.json handshake."""

    def __init__(self) -> None:
        self.root = tk.Tk()
        self.root.title("Nixo Control Center")
        self.root.geometry("920x780")
        self.root.minsize(*WINDOW_MIN)
        self.root.configure(bg=theme.BG)
        theme.setup_styles(self.root)

        self.processes = ProcessManager()
        self._snapshot: status.Snapshot | None = None
        self._log_seen: dict[str, str] = {}

        self._build()
        self.root.protocol("WM_DELETE_WINDOW", self.close)
        self._ensure_control_file()
        self._refresh()

    # ---------------------------------------------------------------- layout
    def _build(self) -> None:
        page = ttk.Frame(self.root, padding=(26, 22, 26, 18))
        page.pack(fill="both", expand=True)

        ttk.Label(page, text="NIXO", style="Title.TLabel").pack(anchor="w")
        ttk.Label(
            page,
            text="CONTROL CENTER  ·  EXTERNAL SIGNALS + TELEGRAM  ·  DEMO GATED",
            style="Subtitle.TLabel",
        ).pack(anchor="w", pady=(0, 16))

        banner = ttk.Frame(page, style="Panel.TFrame", padding=(18, 14))
        banner.pack(fill="x")
        self.state_label = ttk.Label(banner, text="SYSTEM OFF", style="PanelValue.TLabel",
                                     font=(theme.FONT, 22, "bold"))
        self.state_label.pack(side="left")
        self.detail_label = ttk.Label(
            banner, text="", style="PanelDetail.TLabel", wraplength=470, justify="left"
        )
        self.detail_label.pack(side="left", padx=(18, 0))
        self.toggle_button = ttk.Button(
            banner, text="TURN SYSTEM ON", style="Primary.TButton", command=self.toggle
        )
        self.toggle_button.pack(side="right")

        cards = ttk.Frame(page)
        cards.pack(fill="x", pady=(16, 0))
        self.cards: dict[str, StatusCard] = {}
        for column, (key, title) in enumerate((
            ("mt5", "MT5 / account"),
            ("telegram", "Telegram"),
            ("bridge", "Signal bridge"),
            ("ea", "Nixo EA"),
        )):
            card = StatusCard(cards, title, "checking", "")
            card.grid(row=0, column=column, sticky="nsew",
                      padx=(0 if column == 0 else 10, 0))
            cards.columnconfigure(column, weight=1)
            self.cards[key] = card

        checklist = ttk.Frame(page, style="Panel.TFrame", padding=(16, 12))
        checklist.pack(fill="x", pady=(14, 0))
        ttk.Label(checklist, text="SETUP CHECKLIST", style="PanelLabel.TLabel").pack(anchor="w")
        self.check_rows: list[CheckRow] = []
        for _ in range(5):
            row = CheckRow(checklist)
            row.pack(fill="x", pady=(4, 0))
            self.check_rows.append(row)

        ttk.Label(page, text="ACTIVITY LOG", style="Section.TLabel").pack(anchor="w", pady=(16, 6))
        self.activity = ActivityLog(page)
        self.activity.pack(fill="both", expand=True)

        footer = ttk.Frame(page)
        footer.pack(fill="x", pady=(14, 0))
        ttk.Button(footer, text="SETUP", style="Ghost.TButton",
                   command=self.open_setup).pack(side="left")
        ttk.Button(footer, text="INSTALL / UPDATE EA", style="Ghost.TButton",
                   command=self.open_installer).pack(side="left", padx=(8, 0))
        ttk.Button(footer, text="TELEGRAM SOURCES", style="Ghost.TButton",
                   command=self.open_sources).pack(side="left", padx=(8, 0))
        ttk.Button(footer, text="AI BRIDGE", style="Ghost.TButton",
                   command=self.toggle_ai).pack(side="left", padx=(8, 0))
        ttk.Button(footer, text="OPEN BRIDGE FOLDER", style="Ghost.TButton",
                   command=self.open_common).pack(side="right")
# --------------------------------------------------------------- state
    def _control_path(self):
        return paths.nixo_common_dir() / "control.json"

    def _ensure_control_file(self) -> None:
        """Install an OFF command so the EA never runs controller-less by accident."""
        from bridge.control_protocol import load_control, write_control

        try:
            if load_control(self._control_path()) is None:
                write_control(self._control_path(), False)
                self.activity.append("Control file created with system OFF.")
        except (OSError, ValueError) as exc:
            self.activity.append(f"Control protocol unavailable: {exc}", "bad")

    def _refresh(self) -> None:
        try:
            snapshot = status.collect()
        except Exception as exc:  # keep the window alive on any read failure
            self.activity.append(f"Status read failed: {exc}", "bad")
            self.root.after(REFRESH_MS, self._refresh)
            return
        self._snapshot = snapshot
        self._render(snapshot)
        self.root.after(REFRESH_MS, self._refresh)

    def _render(self, snap: status.Snapshot) -> None:
        color = theme.ACCENT if snap.healthy else (
            theme.TEXT if not snap.enabled else theme.DANGER
        )
        self.state_label.configure(text=snap.headline, foreground=color)
        self.toggle_button.configure(
            text="TURN SYSTEM OFF" if snap.enabled else "TURN SYSTEM ON"
        )

        if snap.enabled and snap.healthy:
            detail = "New signals are accepted and traded with the EA money management."
        elif snap.enabled:
            detail = snap.blockers[0] if snap.blockers else "Waiting for the EA heartbeat."
        else:
            detail = (
                "OFF stops new signal intake only. Open positions, pending orders, "
                "SL/TP and EA management stay untouched."
            )
        self.detail_label.configure(text=detail)

        account = "DEMO" if snap.ea_demo else "UNKNOWN"
        self.cards["mt5"].update_value(
            account if snap.ea_online else "OFFLINE",
            f"{snap.ea_symbol} · {snap.ea_mode}" if snap.ea_online else "Attach the EA in MetaTrader",
            theme.ACCENT if snap.ea_online and snap.ea_demo else theme.DANGER
            if snap.ea_online else theme.MUTED,
        )
        self.cards["telegram"].update_value(
            "CONFIGURED" if snap.configured_sources else "NO CHANNELS",
            f"{snap.configured_sources} enabled source(s)",
            theme.ACCENT if snap.configured_sources else theme.WARN,
        )
        self.cards["bridge"].update_value(
            "RUNNING" if snap.bridge_running else "STOPPED",
            f"{snap.bridge_sources} active source(s)" if snap.bridge_running else "Started by TURN ON",
            theme.ACCENT if snap.bridge_running else theme.MUTED,
        )
        self.cards["ea"].update_value(
            f"v{snap.ea_version}" if snap.ea_version else "NOT CONNECTED",
            f"{'LIVE' if snap.ea_live else 'PAPER'} · lab {'on' if snap.ea_signal_lab else 'off'}",
            theme.ACCENT if snap.ea_online else theme.MUTED,
        )

        for row, check in zip(self.check_rows, snap.checks):
            row.update_row(check.title, check.detail, check.ok, check.required)

    # -------------------------------------------------------------- actions
    def toggle(self) -> None:
        from bridge.control_protocol import write_control

        snap = self._snapshot or status.collect()
        if snap.enabled:
            self._set_enabled(False)
            return

        blocking = [check for check in snap.checks if check.required and not check.ok]
        if blocking:
            messagebox.showerror(
                "Setup incomplete",
                "\n".join(f"- {check.title}: {check.detail}" for check in blocking),
                parent=self.root,
            )
            return
        if not snap.ea_online:
            messagebox.showerror(
                "MT5 / Nixo EA unavailable",
                "Open MetaTrader 5 and attach the Nixo EA to a chart. "
                "A fresh EA heartbeat is required before signals can be enabled.",
                parent=self.root,
            )
            return
        if not snap.ea_demo:
            messagebox.showerror(
                "Demo account required",
                "This build only enables signal intake when the EA reports a Demo account.",
                parent=self.root,
            )
            return
        if not snap.ea_signal_lab:
            messagebox.showerror(
                "Signal Lab is disabled",
                "Enable InpSignalLabEnabled in the EA inputs and reload it before turning the system on.",
                parent=self.root,
            )
            return

        state = self.processes.start_bridge()
        self.activity.append(state.detail, "good" if state.running else "warn")
        if not TELEGRAM_SESSION.exists():
            self.activity.append(
                "First Telegram login: use the console window to enter the phone number and code.",
                "warn",
            )
        self._set_enabled(True)

    def _set_enabled(self, enabled: bool) -> None:
        from bridge.control_protocol import write_control

        try:
            write_control(self._control_path(), enabled)
        except OSError as exc:
            messagebox.showerror("Could not write control.json", str(exc), parent=self.root)
            return
        if enabled:
            self.activity.append("System ON — EA switched to EXTERNAL and accepts new signals.", "good")
        else:
            self.processes.stop("bridge")
            self.activity.append(
                "System OFF — new signals blocked; open trades and SL/TP untouched.", "warn"
            )
        self._refresh_now()

    def _refresh_now(self) -> None:
        try:
            self._render(status.collect())
        except Exception as exc:
            self.activity.append(f"Status read failed: {exc}", "bad")

    def toggle_ai(self) -> None:
        if self.processes.is_running("ai"):
            self.processes.stop("ai")
            self.activity.append("AI advisory bridge stopped.")
            return
        state = self.processes.start_ai_bridge()
        self.activity.append(state.detail, "good" if state.running else "warn")

    def open_setup(self) -> None:
        SetupDialog(self.root, on_saved=self._on_setup_saved)

    def _on_setup_saved(self) -> None:
        self.activity.append("Setup saved to bridge/.env.local and ai_bridge/.env.local.", "good")
        self._refresh_now()

    def open_installer(self) -> None:
        InstallerDialog(self.root, on_log=self.activity.append)

    def open_sources(self) -> None:
        SourceManager(self.root, on_change=self._refresh_now)

    def open_common(self) -> None:
        from .setup_state import open_in_explorer

        try:
            open_in_explorer(paths.nixo_common_dir())
        except OSError as exc:
            messagebox.showerror("Could not open folder", str(exc), parent=self.root)

    def close(self) -> None:
        if self._snapshot is not None and self._snapshot.enabled:
            if not messagebox.askokcancel(
                "Turn the system off?",
                "Closing the Control Center switches the system OFF. "
                "Open positions and pending orders are not modified.",
                parent=self.root,
            ):
                return
            self._set_enabled(False)
        self.processes.stop_all()
        self.root.destroy()

    def run(self) -> None:
        self.root.mainloop()
