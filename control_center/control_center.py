#!/usr/bin/env python3
"""Nixo Signal Control Center (Tkinter).

Master ON/OFF gate for Telegram→MT5 Demo signal copy, plus per-source enable/disable
and health monitoring. Writes control.json (fail-closed) and edits
config/sources.json (source enable/channel). Never places trades.
"""
from __future__ import annotations

import asyncio
import json
import os
import sys
import threading
import time
import tkinter as tk
from pathlib import Path
from tkinter import messagebox, simpledialog, ttk

ROOT = Path(__file__).resolve().parent.parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from shared.control_protocol import (  # noqa: E402
    allow_new_intake,
    default_control,
    ea_status_fresh,
    is_master_armed,
    read_control,
    read_ea_status,
    sources_from_config,
    write_control,
)
from control_center.source_wizard import SourceWizard  # noqa: E402

APP_TITLE = "Nixo Control Center — Telegram → MT5 Demo"
CONFIG_PATH = ROOT / "config" / "sources.json"
POLL_MS = 2000


def _load_sources() -> list[dict]:
    try:
        data = json.loads(CONFIG_PATH.read_text(encoding="utf-8-sig"))
    except (OSError, json.JSONDecodeError):
        return []
    return data.get("sources", []) if isinstance(data, dict) else []


def _save_sources(sources: list[dict]) -> None:
    tmp = CONFIG_PATH.with_suffix(".tmp")
    tmp.write_text(json.dumps({"sources": sources}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    os.replace(tmp, CONFIG_PATH)


class ControlCenter(tk.Tk):
    def __init__(self) -> None:
        super().__init__()
        self.title(APP_TITLE)
        self.geometry("760x520")
        self.minsize(700, 460)

        self.master_var = tk.BooleanVar(value=False)
        self.source_items: list[dict] = []
        self.source_vars: list[tk.BooleanVar] = []
        self.status_var = tk.StringVar(value="Initializing…")
        self.health_var = tk.StringVar(value="Health: unknown")
        self.demo_var = tk.StringVar(value="Trade mode: —")
        self.last_update_var = tk.StringVar(value="Last update: —")
        self._after_id: str | None = None
        self._telethon_thread: threading.Thread | None = None
        self._stop_event = threading.Event()

        self._build_ui()
        self.refresh()
        self.after(POLL_MS, self._poll)

    # ------------------------------------------------------------------ UI
    def _build_ui(self) -> None:
        pad = {"padx": 10, "pady": 6}

        top = ttk.Frame(self)
        top.pack(fill=tk.X, **pad)

        ttk.Label(top, text=APP_TITLE, font=("Segoe UI", 12, "bold")).pack(side=tk.LEFT)
        ttk.Separator(top, orient=tk.VERTICAL).pack(side=tk.LEFT, fill=tk.Y, padx=10)
        ttk.Button(top, text="Refresh", command=self.refresh).pack(side=tk.LEFT)
        ttk.Button(top, text="Source Manager", command=self.open_source_manager).pack(side=tk.LEFT, padx=6)
        ttk.Button(top, text="Telegram Login", command=self.open_telegram_login).pack(side=tk.LEFT, padx=6)
        ttk.Button(top, text="Exit", command=self.destroy).pack(side=tk.RIGHT)

        # Master gate card
        gate = ttk.LabelFrame(self, text="Master Signal Gate (Demo only)")
        gate.pack(fill=tk.X, **pad)

        self.master_btn = tk.Button(
            gate, text="MASTER OFF", bg="#c44", fg="white",
            font=("Segoe UI", 11, "bold"), width=16, height=2,
            command=self.toggle_master,
        )
        self.master_btn.pack(side=tk.LEFT, padx=10, pady=8)

        info = ttk.Frame(gate)
        info.pack(side=tk.LEFT, fill=tk.X, expand=True, padx=10)
        ttk.Label(info, textvariable=self.status_var, font=("Segoe UI", 10)).pack(anchor=tk.W)
        ttk.Label(info, textvariable=self.health_var, foreground="#555").pack(anchor=tk.W)
        ttk.Label(info, textvariable=self.demo_var, foreground="#555").pack(anchor=tk.W)
        ttk.Label(info, textvariable=self.last_update_var, foreground="#555").pack(anchor=tk.W)

        # Source list card
        src = ttk.LabelFrame(self, text="Signal Sources (per-channel enable/disable)")
        src.pack(fill=tk.BOTH, expand=True, **pad)

        cols = ("enabled", "name", "type", "endpoint", "source_id")
        self.tree = ttk.Treeview(src, columns=cols, show="headings", selectmode="browse", height=8)
        self.tree.heading("enabled", text="ON/OFF")
        self.tree.heading("name", text="Name")
        self.tree.heading("type", text="Type")
        self.tree.heading("endpoint", text="Channel / Feed")
        self.tree.heading("source_id", text="Source ID")
        self.tree.column("enabled", width=70, anchor=tk.CENTER)
        self.tree.column("name", width=150)
        self.tree.column("type", width=80)
        self.tree.column("endpoint", width=220)
        self.tree.column("source_id", width=130)
        self.tree.pack(fill=tk.BOTH, expand=True, padx=6, pady=6)
        self.tree.bind("<Double-1>", self._toggle_selected)

        btns = ttk.Frame(src)
        btns.pack(fill=tk.X, padx=6, pady=(0, 6))
        ttk.Button(btns, text="Toggle selected", command=self._toggle_selected).pack(side=tk.LEFT)
        ttk.Button(btns, text="Add source", command=self.add_source).pack(side=tk.LEFT, padx=6)
        ttk.Button(btns, text="Remove selected", command=self.remove_source).pack(side=tk.LEFT, padx=6)
        ttk.Button(btns, text="Apply master to sources", command=self.apply_master_to_sources).pack(side=tk.RIGHT)

        bottom = ttk.Frame(self)
        bottom.pack(fill=tk.X, **pad)
        ttk.Label(bottom, text="OFF = no NEW signal intake (existing positions/pending orders untouched). "
                               "Demo account required for live copy.", foreground="#888").pack(side=tk.LEFT)

    # ------------------------------------------------------------------ refresh / poll
    def refresh(self) -> None:
        self._refresh_master()
        self._refresh_health()
        self._refresh_sources()
        self.last_update_var.set(f"Last update: {time.strftime('%H:%M:%S')}")

    def _poll(self) -> None:
        self.refresh()
        self._after_id = self.after(POLL_MS, self._poll)

    def _refresh_master(self) -> None:
        try:
            armed = is_master_armed(ROOT)
        except Exception as exc:  # pragma: no cover - defensive
            armed = False
            self.status_var.set(f"control.json read error: {exc}")
        self.master_var.set(armed)
        if armed:
            self.master_btn.config(text="MASTER ON", bg="#4c4", fg="#111")
            self.status_var.set("Master armed: ON — NEW signal intake allowed (Demo gate still enforced in EA)")
        else:
            self.master_btn.config(text="MASTER OFF", bg="#c44", fg="white")
            self.status_var.set("Master armed: OFF — no NEW signal intake")

    def _refresh_health(self) -> None:
        fresh = ea_status_fresh(ROOT)
        status = read_ea_status(ROOT) or {}
        mode = str(status.get("trade_mode", "")).upper() or "—"
        signal_live = bool(status.get("signal_live"))
        trading = str(status.get("trading_mode", "")).upper() or "—"
        self.demo_var.set(f"Trade mode: {mode} | External: {trading} | Signal live: {signal_live}")
        if fresh:
            self.health_var.set("EA heartbeat: FRESH ✓")
            self.health_var.set(self.health_var.get().replace("✓", "✓"))  # keep color neutral
        else:
            self.health_var.set("EA heartbeat: STALE or missing — intake blocked")

    def _refresh_sources(self) -> None:
        for item in self.tree.get_children():
            self.tree.delete(item)
        self.source_items = _load_sources()
        self.source_vars = []
        control = read_control(ROOT) or {}
        control_source_ids = {str(s.get("id", "")) for s in control.get("sources", []) if s.get("enabled")}
        for src in self.source_items:
            enabled = bool(src.get("enabled"))
            var = tk.BooleanVar(value=enabled)
            self.source_vars.append(var)
            sid = str(src.get("id", ""))
            stype = str(src.get("source_type", "telegram")).upper()
            endpoint = src.get("channel") or src.get("feed_url", "")
            name = src.get("name") or sid
            self.tree.insert("", tk.END, iid=sid, values=(
                "ON" if enabled else "OFF", name, stype, endpoint, sid,
            ))
            # reflect control.json source arming in the tag color
            if sid in control_source_ids and enabled:
                self.tree.item(sid, tags=("armed",))
            else:
                self.tree.item(sid, tags=("disarmed",))
        self.tree.tag_configure("armed", foreground="#0a0")
        self.tree.tag_configure("disarmed", foreground="#777")

    # ------------------------------------------------------------------ master toggle
    def toggle_master(self) -> None:
        wanted = not bool(self.master_var.get())
        control = read_control(ROOT) or default_control()
        control["master_armed"] = wanted
        # mirror per-source enable state into control.json sources list
        src_list = []
        for src, var in zip(self.source_items, self.source_vars):
            sid = str(src.get("id", ""))
            if sid:
                src_list.append({"id": sid, "enabled": bool(var.get())})
        control["sources"] = src_list
        try:
            write_control(ROOT, control)
            self.master_var.set(wanted)
            self.status_var.set(f"Master {'armed (ON)' if wanted else 'disarmed (OFF)'} — written to control.json")
        except Exception as exc:  # pragma: no cover - defensive
            messagebox.showerror("Write failed", f"Could not write control.json:\n{exc}")
            return
        self._refresh_master()
        self._refresh_sources()

    def apply_master_to_sources(self) -> None:
        armed = bool(self.master_var.get())
        for var in self.source_vars:
            var.set(armed)
        self.toggle_master()

    # ------------------------------------------------------------------ source toggles
    def _toggle_selected(self, event=None) -> None:
        sel = self.tree.selection()
        if not sel:
            return
        sid = sel[0]
        idx = next((i for i, s in enumerate(self.source_items) if str(s.get("id", "")) == sid), None)
        if idx is None:
            return
        self.source_vars[idx].set(not bool(self.source_vars[idx].get()))
        self.toggle_master()

    def add_source(self) -> None:
        wizard = SourceWizard(self, CONFIG_PATH, self.source_items, mode="add")
        self.wait_window(wizard)
        if wizard.result:
            self.source_items.append(wizard.result)
            _save_sources(self.source_items)
            self._refresh_sources()

    def remove_source(self) -> None:
        sel = self.tree.selection()
        if not sel:
            messagebox.showinfo("Remove source", "Select a source row first.")
            return
        sid = sel[0]
        src = next((s for s in self.source_items if str(s.get("id", "")) == sid), None)
        if not src:
            return
        if not messagebox.askyesno("Remove source", f"Remove source '{src.get('name', sid)}'?"):
            return
        self.source_items = [s for s in self.source_items if str(s.get("id", "")) != sid]
        _save_sources(self.source_items)
        self._refresh_sources()

    # ------------------------------------------------------------------ wizards
    def open_source_manager(self) -> None:
        wizard = SourceWizard(self, CONFIG_PATH, self.source_items, mode="manage")
        self.wait_window(wizard)
        if wizard.result is not None:
            self.source_items = wizard.result
            _save_sources(self.source_items)
            self._refresh_sources()

    def open_telegram_login(self) -> None:
        api_id = simpledialog.askstring("Telegram Login", "API ID (from my.telegram.org):", parent=self)
        if api_id is None:
            return
        api_hash = simpledialog.askstring("Telegram Login", "API HASH (from my.telegram.org):", parent=self, show="*")
        if api_hash is None:
            return
        phone = simpledialog.askstring("Telegram Login", "Phone number (with country code, e.g. +98912…):", parent=self)
        if phone is None:
            return
        self._stop_event.clear()
        self._telethon_thread = threading.Thread(
            target=self._run_telethon_login, args=(api_id, api_hash, phone), daemon=True,
        )
        self._telethon_thread.start()
        self.status_var.set("Telegram login in progress… check console for code prompt.")

    def _run_telethon_login(self, api_id: str, api_hash: str, phone: str) -> None:
        try:
            from telethon import TelegramClient
        except ImportError:
            self.after(0, lambda: messagebox.showerror(
                "Telethon missing", "Install bridge requirements: pip install -r bridge/requirements.txt"))
            return
        session = ROOT / "nixo_telegram"
        client = TelegramClient(str(session), int(api_id), api_hash)

        async def _login() -> None:
            await client.start(phone=phone)
            me = await client.get_me()
            self.after(0, lambda: self.status_var.set(
                f"Telegram logged in as {me.first_name or ''} {me.last_name or ''} ({me.phone}) — session saved."))
            await client.disconnect()

        try:
            asyncio.run(_login())
        except Exception as exc:  # pragma: no cover - network/auth
            self.after(0, lambda e=exc: messagebox.showerror("Telegram login failed", str(e)))
            self.after(0, lambda: self.status_var.set("Telegram login failed."))

    def destroy(self) -> None:
        if self._after_id is not None:
            self.after_cancel(self._after_id)
        self._stop_event.set()
        super().destroy()


def main() -> int:
    app = ControlCenter()
    app.mainloop()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
