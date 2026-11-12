"""Add/edit form for a single Telegram signal source."""
from __future__ import annotations

import tkinter as tk
from tkinter import messagebox, ttk

from . import theme
from .sources_store import SourceError, parse_symbols


class SourceForm(tk.Toplevel):
    """Modal dialog that edits one Telegram source record."""

    def __init__(self, master: tk.Misc, source: dict | None = None) -> None:
        super().__init__(master)
        self.source = source
        self.result: dict | None = None
        self.title("Edit Telegram source" if source else "Add Telegram source")
        self.configure(bg=theme.BG)
        self.resizable(False, False)
        self.transient(master.winfo_toplevel())
        self.grab_set()

        body = ttk.Frame(self, padding=20)
        body.pack(fill="both", expand=True)
        ttk.Label(body, text="TELEGRAM SOURCE", style="Section.TLabel").grid(
            row=0, column=0, columnspan=2, sticky="w", pady=(0, 12)
        )

        self._entries: dict[str, tk.Entry] = {}
        fields = (
            ("name", "Display name", str(source.get("name", "")) if source else ""),
            ("channel", "Channel username or numeric ID (join private channel first)",
             str(source.get("channel", source.get("channel_id", ""))) if source else ""),
            ("symbols", "Allowed symbols (comma separated)",
             ", ".join(source.get("allowed_symbols", [])) if source else "XAUUSD"),
        )
        for row, (key, label, initial) in enumerate(fields, start=1):
            ttk.Label(body, text=label, style="Hint.TLabel").grid(
                row=row, column=0, sticky="w", pady=6
            )
            entry = tk.Entry(
                body, width=34, background=theme.SURFACE_ALT, foreground=theme.TEXT,
                insertbackground=theme.TEXT, relief="flat", font=(theme.FONT, 10),
            )
            entry.insert(0, initial)
            entry.grid(row=row, column=1, sticky="ew", padx=(14, 0), pady=6, ipady=5)
            self._entries[key] = entry

        self._enabled = tk.BooleanVar(value=bool(source.get("enabled")) if source else False)
        self._single = tk.BooleanVar(
            value=bool(source.get("assume_single_symbol")) if source else False
        )
        for row, (variable, text) in enumerate((
            (self._enabled, "Enable this source now"),
            (self._single, "Assume the only symbol when the post omits a ticker"),
        ), start=4):
            ttk.Checkbutton(body, text=text, variable=variable).grid(
                row=row, column=0, columnspan=2, sticky="w", pady=4
            )

        actions = ttk.Frame(body)
        actions.grid(row=6, column=0, columnspan=2, sticky="e", pady=(18, 0))
        ttk.Button(actions, text="CANCEL", style="Ghost.TButton", command=self.destroy).pack(
            side="left", padx=(0, 8)
        )
        ttk.Button(actions, text="SAVE", style="Primary.TButton", command=self._save).pack(
            side="left"
        )
        body.columnconfigure(1, weight=1)
        self.bind("<Return>", lambda _event: self._save())
        self.bind("<Escape>", lambda _event: self.destroy())
        self._entries["name"].focus_set()

    def _save(self) -> None:
        try:
            symbols = parse_symbols(self._entries["symbols"].get())
        except SourceError as exc:
            messagebox.showerror("Invalid symbols", str(exc), parent=self)
            return
        self.result = {
            "name": self._entries["name"].get().strip(),
            "channel": self._entries["channel"].get().strip(),
            "symbols": symbols,
            "enabled": self._enabled.get(),
            "assume_single_symbol": self._single.get(),
        }
        self.destroy()
