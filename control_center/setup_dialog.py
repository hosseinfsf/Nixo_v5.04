"""First-run setup: Telegram credentials, MT5 folder, and optional AI bridge."""
from __future__ import annotations

import tkinter as tk
from tkinter import messagebox, ttk

from . import theme
from .paths import default_common_files, resolve_common_files
from .setup_state import ai_env, bridge_env, save_ai_env, save_bridge_env


class SetupDialog(tk.Toplevel):
    """Collects everything the bridges need before the system can turn on."""

    def __init__(self, master: tk.Misc, on_saved=None) -> None:
        super().__init__(master)
        self._on_saved = on_saved
        self.title("Nixo · Setup")
        self.configure(bg=theme.BG)
        self.resizable(False, False)
        self.transient(master.winfo_toplevel())
        self.grab_set()

        bridge = bridge_env()
        ai = ai_env()
        body = ttk.Frame(self, padding=22)
        body.pack(fill="both", expand=True)

        ttk.Label(body, text="SETUP", style="Section.TLabel").grid(
            row=0, column=0, columnspan=2, sticky="w", pady=(0, 4)
        )
        ttk.Label(
            body,
            text="Credentials stay in bridge/.env.local on this machine. Never share or commit that file.",
            style="Hint.TLabel",
            wraplength=520,
            justify="left",
        ).grid(row=1, column=0, columnspan=2, sticky="w", pady=(0, 16))

        self._entries: dict[str, tk.Entry] = {}
        rows = self._add_section(body, 2, "TELEGRAM API", (
            ("TELEGRAM_API_ID", "api_id", bridge["TELEGRAM_API_ID"]),
            ("TELEGRAM_API_HASH", "api_hash", bridge["TELEGRAM_API_HASH"]),
        ))
        self._add_section(body, rows, "MT5 COMMON FILES", (
            ("MT5_COMMON_FILES", "Common Files path (blank = auto detect)",
             bridge["MT5_COMMON_FILES"] or str(default_common_files())),
        ))
        rows = self._add_section(body, rows + 2, "AI ADVISORY (OPTIONAL)", (
            ("NIXO_AI_BASE_URL", "Base URL", ai["NIXO_AI_BASE_URL"]),
            ("NIXO_AI_MODEL", "Model", ai["NIXO_AI_MODEL"]),
            ("NIXO_AI_API_KEY", "API key", ai["NIXO_AI_API_KEY"]),
        ))

        actions = ttk.Frame(body)
        actions.grid(row=rows + 1, column=0, columnspan=2, sticky="ew", pady=(20, 0))
        ttk.Button(actions, text="DETECT MT5 FOLDER", style="Ghost.TButton",
                   command=self._detect_common).pack(side="left")
        ttk.Button(actions, text="SAVE", style="Primary.TButton",
                   command=self._save).pack(side="right")
        body.columnconfigure(1, weight=1)
        self._entries["TELEGRAM_API_ID"].focus_set()

    def _add_section(self, body: ttk.Frame, start_row: int, title: str,
                     fields: tuple[tuple[str, str, str], ...]) -> int:
        ttk.Label(body, text=title, style="Section.TLabel").grid(
            row=start_row, column=0, columnspan=2, sticky="w", pady=(10, 6)
        )
        row = start_row + 1
        for key, label, initial in fields:
            ttk.Label(body, text=label, style="Hint.TLabel").grid(
                row=row, column=0, sticky="w", pady=5
            )
            entry = tk.Entry(
                body, width=48, background=theme.SURFACE_ALT, foreground=theme.TEXT,
                insertbackground=theme.TEXT, relief="flat", font=(theme.FONT, 10),
            )
            entry.insert(0, initial)
            entry.grid(row=row, column=1, sticky="ew", padx=(14, 0), pady=5, ipady=5)
            self._entries[key] = entry
            row += 1
        return row

    def _detect_common(self) -> None:
        detected = resolve_common_files()
        self._entries["MT5_COMMON_FILES"].delete(0, "end")
        self._entries["MT5_COMMON_FILES"].insert(0, str(detected))
        messagebox.showinfo("MT5 folder", f"Resolved to:\n{detected}", parent=self)

    def _value(self, key: str) -> str:
        return self._entries[key].get().strip()

    def _save(self) -> None:
        api_id = self._value("TELEGRAM_API_ID")
        api_hash = self._value("TELEGRAM_API_HASH")
        if api_id and not api_id.isdigit():
            messagebox.showerror("Invalid api_id", "api_id must be the numeric value from my.telegram.org.", parent=self)
            return
        if (api_id and not api_hash) or (api_hash and not api_id):
            messagebox.showerror("Incomplete credentials", "Fill in both api_id and api_hash, or leave both blank.", parent=self)
            return
        if api_hash and len(api_hash) < 20:
            messagebox.showerror("Invalid api_hash", "That api_hash looks too short. Copy it again from my.telegram.org.", parent=self)
            return

        bridge = bridge_env()
        bridge.update({
            "TELEGRAM_API_ID": api_id,
            "TELEGRAM_API_HASH": api_hash,
            "MT5_COMMON_FILES": self._value("MT5_COMMON_FILES"),
        })
        ai = ai_env()
        ai.update({
            "NIXO_AI_BASE_URL": self._value("NIXO_AI_BASE_URL"),
            "NIXO_AI_MODEL": self._value("NIXO_AI_MODEL"),
            "NIXO_AI_API_KEY": self._value("NIXO_AI_API_KEY"),
        })
        try:
            save_bridge_env(bridge)
            save_ai_env(ai)
        except OSError as exc:
            messagebox.showerror("Could not save setup", str(exc), parent=self)
            return
        if self._on_saved is not None:
            self._on_saved()
        self.destroy()
