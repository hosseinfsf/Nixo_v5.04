#!/usr/bin/env python3
"""First Windows Control Center slice: Demo-gated external signal ON/OFF."""
from __future__ import annotations

import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time
import tkinter as tk
from tkinter import messagebox, ttk

ROOT = Path(__file__).resolve().parents[1]
BRIDGE_DIR = ROOT / "bridge"
CONFIG_FILE = ROOT / "config" / "sources.json"


def resolve_common_files() -> Path:
    configured = os.environ.get("MT5_COMMON_FILES", "").strip()
    if not configured:
        env_file = BRIDGE_DIR / ".env.local"
        try:
            for raw_line in env_file.read_text(encoding="utf-8-sig").splitlines():
                line = raw_line.strip()
                if line.startswith("MT5_COMMON_FILES="):
                    configured = line.split("=", 1)[1].strip().strip("\"'")
                    break
        except FileNotFoundError:
            pass
        except OSError as exc:
            raise RuntimeError(f"Could not read the MT5 Common Files setting: {exc}") from exc
    if not configured:
        try:
            config = json.loads(CONFIG_FILE.read_text(encoding="utf-8"))
        except (OSError, ValueError) as exc:
            raise RuntimeError(f"Could not read the bridge configuration: {exc}") from exc
        if not isinstance(config, dict):
            raise RuntimeError("The bridge configuration must contain a JSON object.")
        configured = str(config.get("mt5_common_files", "")).strip()
    if configured:
        return Path(configured).expanduser().resolve()
    appdata = os.environ.get("APPDATA")
    if appdata:
        return Path(appdata) / "MetaQuotes" / "Terminal" / "Common" / "Files"
    return Path.home() / "AppData" / "Roaming" / "MetaQuotes" / "Terminal" / "Common" / "Files"


COMMON_FILES = resolve_common_files()
NIXO_FILES = COMMON_FILES / "NixoBridge"

sys.path.insert(0, str(ROOT))
from bridge.control_protocol import control_enabled, load_control, write_control


def read_json(path: Path) -> dict | None:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return None
    if not isinstance(value, dict):
        raise ValueError(f"{path.name} must contain a JSON object")
    return value


def heartbeat_is_fresh(data: dict | None, key: str, max_age: int = 15) -> bool:
    if data is None:
        return False
    try:
        age = time.time() - int(data[key])
    except (KeyError, TypeError, ValueError):
        return False
    return 0 <= age <= max_age


class ControlCenter:
    def __init__(self) -> None:
        self.root = tk.Tk()
        self.root.title("NIXO CONTROL CENTER")
        self.root.geometry("680x520")
        self.root.minsize(620, 480)
        self.root.configure(bg="#101820")
        self.bridge_process: subprocess.Popen | None = None
        self._build_ui()
        self.root.protocol("WM_DELETE_WINDOW", self.close)
        try:
            if load_control(NIXO_FILES / "control.json") is None:
                write_control(NIXO_FILES / "control.json", False)
        except (OSError, ValueError) as exc:
            messagebox.showerror("Control Protocol unavailable", str(exc), parent=self.root)
        self.refresh()

    def _build_ui(self) -> None:
        style = ttk.Style(self.root)
        style.theme_use("clam")
        style.configure("TFrame", background="#101820")
        style.configure("TLabel", background="#101820", foreground="#e7edf2", font=("Segoe UI", 11))
        style.configure("Title.TLabel", font=("Segoe UI", 27, "bold"), foreground="#f2f6fa")
        style.configure("Muted.TLabel", foreground="#9caeba", font=("Segoe UI", 10))
        style.configure("Card.TFrame", background="#1a2731")
        style.configure("CardTitle.TLabel", background="#1a2731", foreground="#9caeba", font=("Segoe UI", 9, "bold"))
        style.configure("CardValue.TLabel", background="#1a2731", foreground="#f2f6fa", font=("Segoe UI", 14, "bold"))
        style.configure("TButton", font=("Segoe UI", 10, "bold"), padding=(14, 9))

        page = ttk.Frame(self.root, padding=24)
        page.pack(fill="both", expand=True)
        ttk.Label(page, text="NIXO", style="Title.TLabel").pack(anchor="w")
        ttk.Label(page, text="CONTROL CENTER  ·  v1.0  ·  DEMO ONLY", style="Muted.TLabel").pack(anchor="w", pady=(0, 20))

        self.state_label = ttk.Label(page, text="SYSTEM OFF", style="CardValue.TLabel", anchor="center")
        self.state_label.pack(fill="x", ipady=18, pady=(0, 14))
        self.toggle_button = ttk.Button(page, text="TURN SYSTEM ON", command=self.toggle)
        self.toggle_button.pack(fill="x", pady=(0, 20))

        cards = ttk.Frame(page)
        cards.pack(fill="x")
        self.status_values: dict[str, ttk.Label] = {}
        for column, (key, title) in enumerate((
            ("mt5", "MT5 / ACCOUNT"),
            ("telegram", "TELEGRAM BRIDGE"),
            ("ea", "NIXO EA"),
        )):
            card = ttk.Frame(cards, style="Card.TFrame", padding=14)
            card.grid(row=0, column=column, sticky="nsew", padx=(0 if column == 0 else 8, 0))
            ttk.Label(card, text=title, style="CardTitle.TLabel").pack(anchor="w")
            value = ttk.Label(card, text="Checking…", style="CardValue.TLabel")
            value.pack(anchor="w", pady=(10, 0))
            self.status_values[key] = value
            cards.columnconfigure(column, weight=1)

        ttk.Label(page, text="EXTERNAL SIGNAL SYSTEM", style="Muted.TLabel").pack(anchor="w", pady=(24, 8))
        self.detail_label = ttk.Label(
            page,
            text="OFF stops new signal intake. Existing positions, pending orders, SL/TP, and EA trade management are left untouched.",
            wraplength=610,
            justify="left",
        )
        self.detail_label.pack(anchor="w")

        buttons = ttk.Frame(page)
        buttons.pack(fill="x", side="bottom", pady=(24, 0))
        ttk.Button(buttons, text="MANAGE TELEGRAM SOURCES", command=self.open_sources).pack(side="left")
        ttk.Button(buttons, text="OPEN COMMON FILES", command=self.open_common_files).pack(side="right")

    def _load_control_enabled(self) -> bool:
        try:
            control = load_control(NIXO_FILES / "control.json")
        except (OSError, ValueError):
            return False
        return control_enabled(control) if control is not None else False

    def _ea_status(self) -> dict | None:
        try:
            return read_json(NIXO_FILES / "ea_status.json")
        except (OSError, ValueError):
            return None

    def _bridge_status(self) -> dict | None:
        try:
            return read_json(NIXO_FILES / "bridge_status.json")
        except (OSError, ValueError):
            return None

    def refresh(self) -> None:
        ea = self._ea_status()
        bridge = self._bridge_status()
        ea_fresh = heartbeat_is_fresh(ea, "heartbeat")
        bridge_fresh = heartbeat_is_fresh(bridge, "last_heartbeat", 12)
        enabled = self._load_control_enabled()

        if (
            enabled
            and ea_fresh
            and ea
            and ea.get("demo_account") is True
            and ea.get("system_enabled") is True
            and ea.get("signal_lab_enabled") is True
        ):
            self.state_label.configure(text="SYSTEM ON", foreground="#39d98a")
        elif enabled:
            self.state_label.configure(text="SYSTEM BLOCKED", foreground="#ff6b6b")
        else:
            self.state_label.configure(text="SYSTEM OFF", foreground="#ff6b6b")
        if enabled:
            self.toggle_button.configure(text="TURN SYSTEM OFF")
        else:
            self.toggle_button.configure(text="TURN SYSTEM ON")

        account = "DEMO" if ea and ea.get("demo_account") is True else (
            "REAL — BLOCKED" if ea and ea.get("demo_account") is False else "UNKNOWN"
        )
        self.status_values["mt5"].configure(
            text=account if ea_fresh else "MT5 OFFLINE",
            foreground="#39d98a" if ea_fresh and account == "DEMO" else "#ff6b6b",
        )
        self.status_values["telegram"].configure(
            text="Running" if bridge_fresh and bridge and bridge.get("running") else "Stopped",
            foreground="#39d98a" if bridge_fresh and bridge and bridge.get("running") else "#9caeba",
        )
        mode = str(ea.get("trading_mode", "Unknown")) if ea else "Unknown"
        version = str(ea.get("ea_version", "")) if ea else ""
        execution = "LIVE" if ea and ea.get("signal_live_enabled") is True else "PAPER"
        self.status_values["ea"].configure(
            text=f"{version} · {mode} · {execution}" if ea_fresh else "Not connected",
            foreground="#39d98a" if ea_fresh else "#ff6b6b",
        )
        self.root.after(2000, self.refresh)

    def _start_bridge(self) -> None:
        bridge = self._bridge_status()
        if (
            bridge is not None
            and bridge.get("running") is True
            and heartbeat_is_fresh(bridge, "last_heartbeat", 12)
        ):
            return
        if self.bridge_process is not None and self.bridge_process.poll() is None:
            return
        flags = subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0
        session = BRIDGE_DIR / "nixo_telegram.session"
        if not session.exists():
            flags = 0
        self.bridge_process = subprocess.Popen(
            [sys.executable, str(BRIDGE_DIR / "signal_bridge.py")],
            cwd=BRIDGE_DIR,
            creationflags=flags,
        )

    def toggle(self) -> None:
        if self._load_control_enabled():
            try:
                write_control(NIXO_FILES / "control.json", False)
            except OSError as exc:
                messagebox.showerror("Could not stop Nixo", str(exc), parent=self.root)
                return
            self.refresh()
            return

        ea = self._ea_status()
        if not heartbeat_is_fresh(ea, "heartbeat") or not ea or ea.get("running") is not True:
            messagebox.showerror(
                "MT5 / Nixo EA unavailable",
                "Open MT5 and attach the Control Protocol-enabled Nixo EA. A fresh EA heartbeat is required.",
                parent=self.root,
            )
            return
        if ea.get("demo_account") is not True:
            messagebox.showerror(
                "Demo account required",
                "Nixo Control Center will not enable signal intake unless the EA confirms a Demo account.",
                parent=self.root,
            )
            return
        if ea.get("signal_lab_enabled") is not True:
            messagebox.showerror(
                "Signal Lab is disabled",
                "Enable InpSignalLabEnabled in the EA and reload it before turning the system on.",
                parent=self.root,
            )
            return
        try:
            self._start_bridge()
            write_control(NIXO_FILES / "control.json", True)
        except (OSError, subprocess.SubprocessError) as exc:
            messagebox.showerror("Could not start Nixo", str(exc), parent=self.root)
            return
        self.refresh()

    def open_common_files(self) -> None:
        NIXO_FILES.mkdir(parents=True, exist_ok=True)
        os.startfile(str(NIXO_FILES))

    def open_sources(self) -> None:
        SourceManager(self.root)

    def close(self) -> None:
        if self._load_control_enabled():
            try:
                write_control(NIXO_FILES / "control.json", False)
            except OSError as exc:
                messagebox.showerror("Could not stop Nixo", str(exc), parent=self.root)
                return
        if self.bridge_process is not None and self.bridge_process.poll() is None:
            self.bridge_process.terminate()
        self.root.destroy()

    def run(self) -> None:
        self.root.mainloop()


class SourceManager(tk.Toplevel):
    def __init__(self, parent: tk.Tk) -> None:
        super().__init__(parent)
        self.title("Telegram Source Manager")
        self.geometry("760x420")
        self.configure(bg="#101820")
        self.sources: list[dict] = []
        self.tree = ttk.Treeview(
            self,
            columns=("name", "channel", "symbols", "enabled"),
            show="headings",
            selectmode="browse",
        )
        for column, title, width in (
            ("name", "SOURCE", 180),
            ("channel", "TELEGRAM CHANNEL", 180),
            ("symbols", "ALLOWED SYMBOLS", 210),
            ("enabled", "STATE", 90),
        ):
            self.tree.heading(column, text=title)
            self.tree.column(column, width=width, anchor="w")
        self.tree.pack(fill="both", expand=True, padx=16, pady=(16, 8))

        actions = ttk.Frame(self)
        actions.pack(fill="x", padx=16, pady=(0, 12))
        ttk.Button(actions, text="ADD CHANNEL", command=self.add_channel).pack(side="left")
        ttk.Button(actions, text="EDIT", command=self.edit_channel).pack(side="left", padx=6)
        ttk.Button(actions, text="ON / OFF", command=self.toggle_channel).pack(side="left")
        ttk.Button(actions, text="REMOVE", command=self.remove_channel).pack(side="left", padx=6)
        ttk.Button(actions, text="RELOAD", command=self.reload).pack(side="right")
        self.reload()

    def reload(self) -> None:
        try:
            data = read_json(CONFIG_FILE)
            if data is None or not isinstance(data.get("sources"), list):
                raise ValueError("config/sources.json must contain a sources list")
        except (OSError, ValueError) as exc:
            messagebox.showerror("Could not load sources", str(exc), parent=self)
            return
        self.sources = data["sources"]
        self.tree.delete(*self.tree.get_children())
        for source in self.sources:
            if str(source.get("source_type", "telegram")).lower() != "telegram":
                continue
            self.tree.insert(
                "",
                "end",
                iid=str(source.get("id", "")),
                values=(
                    source.get("name", ""),
                    source.get("channel", source.get("channel_id", "")),
                    ", ".join(source.get("allowed_symbols", [])),
                    "ON" if source.get("enabled") else "OFF",
                ),
            )

    def _selected(self) -> dict | None:
        selected = self.tree.selection()
        if not selected:
            messagebox.showinfo("Select a channel", "Choose a Telegram source first.", parent=self)
            return None
        source_id = selected[0]
        return next((source for source in self.sources if str(source.get("id")) == source_id), None)

    def add_channel(self) -> None:
        self._channel_form()

    def edit_channel(self) -> None:
        source = self._selected()
        if source is not None:
            self._channel_form(source)

    def _channel_form(self, source: dict | None = None) -> None:
        dialog = tk.Toplevel(self)
        dialog.title("Edit Telegram Source" if source else "Add Telegram Source")
        dialog.transient(self)
        dialog.grab_set()
        dialog.configure(bg="#101820")
        fields = (
            ("Display name", str(source.get("name", "")) if source else ""),
            ("Telegram username (without @)", str(source.get("channel", "")) if source else ""),
            ("Allowed symbols (comma-separated)", ", ".join(source.get("allowed_symbols", [])) if source else "XAUUSD"),
        )
        entries: list[tk.Entry] = []
        for row, (label, initial) in enumerate(fields):
            ttk.Label(dialog, text=label).grid(row=row, column=0, sticky="w", padx=12, pady=8)
            entry = tk.Entry(dialog, width=38)
            entry.insert(0, initial)
            entry.grid(row=row, column=1, padx=12, pady=8)
            entries.append(entry)

        def save() -> None:
            name, channel, symbols_text = (entry.get().strip() for entry in entries)
            channel = channel.lstrip("@")
            if not name or not re.fullmatch(r"[A-Za-z0-9_]{3,}", channel):
                messagebox.showerror("Invalid channel", "Enter a display name and a valid Telegram username.", parent=dialog)
                return
            symbols = list(dict.fromkeys(
                symbol.strip().upper()
                for symbol in symbols_text.split(",")
                if symbol.strip()
            ))
            if not symbols or any(not re.fullmatch(r"[A-Z0-9._-]{1,32}", symbol) for symbol in symbols):
                messagebox.showerror("Invalid symbols", "Enter one or more valid symbols, separated by commas.", parent=dialog)
                return
            source_id = re.sub(r"[^A-Za-z0-9_-]+", "_", channel)[:32]
            try:
                config = read_json(CONFIG_FILE)
            except (OSError, ValueError) as exc:
                messagebox.showerror("Could not load sources", str(exc), parent=dialog)
                return
            if config is None or not isinstance(config.get("sources"), list):
                messagebox.showerror("Could not load sources", "config/sources.json must contain a sources list.", parent=dialog)
                return
            if source is None and any(item.get("id") == source_id for item in config["sources"]):
                messagebox.showerror("Duplicate source", "A source with this ID already exists.", parent=dialog)
                return
            updated = {
                "id": source_id if source is None else source["id"],
                "name": name,
                "source_type": "telegram",
                "enabled": False if source is None else bool(source.get("enabled")),
                "parser": "standard" if source is None else source.get("parser", "standard"),
                "allowed_symbols": symbols,
                "assume_single_symbol": (
                    len(symbols) == 1 and bool(source.get("assume_single_symbol"))
                    if source is not None
                    else False
                ),
                "channel": channel,
            }
            if source is None:
                config["sources"].append(updated)
            else:
                config["sources"] = [
                    updated if item is source else item for item in config["sources"]
                ]
            try:
                self._save_data(config)
            except (OSError, ValueError) as exc:
                messagebox.showerror("Could not save source", str(exc), parent=dialog)
                return
            dialog.destroy()
            self.reload()
            messagebox.showinfo(
                "Source saved",
                "Turn the system OFF and ON to apply source changes to the Bridge.",
                parent=self,
            )

        ttk.Button(dialog, text="SAVE", command=save).grid(row=len(fields), column=1, sticky="e", padx=12, pady=12)

    def _save_data(self, data: dict) -> None:
        descriptor, temporary_name = tempfile.mkstemp(
            prefix=".sources.", suffix=".tmp", dir=CONFIG_FILE.parent
        )
        temporary_path = Path(temporary_name)
        try:
            with os.fdopen(descriptor, "w", encoding="utf-8", newline="\n") as config_file:
                json.dump(data, config_file, ensure_ascii=False, indent=2)
                config_file.write("\n")
                config_file.flush()
                os.fsync(config_file.fileno())
            os.replace(temporary_path, CONFIG_FILE)
        except BaseException:
            temporary_path.unlink(missing_ok=True)
            raise

    def toggle_channel(self) -> None:
        source = self._selected()
        if source is None:
            return
        try:
            data = read_json(CONFIG_FILE)
            if data is None:
                raise ValueError("config/sources.json is missing")
            data["sources"] = [
                {**item, "enabled": not bool(item.get("enabled"))}
                if item is source else item
                for item in self.sources
            ]
            self._save_data(data)
        except (OSError, ValueError) as exc:
            messagebox.showerror("Could not update source", str(exc), parent=self)
            return
        self.reload()

    def remove_channel(self) -> None:
        source = self._selected()
        if source is None or not messagebox.askyesno(
            "Remove source", f"Remove '{source.get('name', source.get('id'))}'?", parent=self
        ):
            return
        try:
            data = read_json(CONFIG_FILE)
            if data is None:
                raise ValueError("config/sources.json is missing")
            data["sources"] = [item for item in self.sources if item is not source]
            self._save_data(data)
        except (OSError, ValueError) as exc:
            messagebox.showerror("Could not remove source", str(exc), parent=self)
            return
        self.reload()


if __name__ == "__main__":
    ControlCenter().run()
