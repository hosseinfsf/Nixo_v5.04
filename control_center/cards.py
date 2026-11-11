"""Reusable status widgets used on the Control Center dashboard."""
from __future__ import annotations

import tkinter as tk
from tkinter import ttk

from . import theme


class StatusCard(ttk.Frame):
    """A titled card showing one subsystem's state and a one-line detail."""

    def __init__(self, master: tk.Misc, title: str, value: str = "", detail: str = "") -> None:
        super().__init__(master, style="Panel.TFrame", padding=(16, 13))
        ttk.Label(self, text=title.upper(), style="PanelLabel.TLabel").pack(anchor="w")
        self._value = ttk.Label(self, text=value or "-", style="PanelValue.TLabel")
        self._value.pack(anchor="w", pady=(7, 0))
        self._detail = ttk.Label(self, text=detail, style="PanelDetail.TLabel", wraplength=190)
        self._detail.pack(anchor="w", pady=(3, 0))

    def update_value(self, value: str, detail: str | None = None,
                     color: str | None = None) -> None:
        self._value.configure(text=value)
        if color is not None:
            self._value.configure(foreground=color)
        if detail is not None:
            self._detail.configure(text=detail)


class CheckRow(ttk.Frame):
    """One line in the setup checklist."""

    def __init__(self, master: tk.Misc) -> None:
        super().__init__(master, style="Panel.TFrame")
        self._mark = ttk.Label(self, text="--", style="PanelDetail.TLabel", width=3)
        self._mark.pack(side="left")
        self._text = ttk.Label(self, text="", style="PanelDetail.TLabel", wraplength=430,
                               justify="left")
        self._text.pack(side="left", fill="x", expand=True, padx=(4, 0))

    def update_row(self, title: str, detail: str, ok: bool, required: bool) -> None:
        if ok:
            mark, color = "OK", theme.ACCENT
        elif required:
            mark, color = "!!", theme.DANGER
        else:
            mark, color = "--", theme.MUTED
        self._mark.configure(text=mark, foreground=color)
        suffix = "" if required else "  (optional)"
        self._text.configure(text=f"{title} - {detail}{suffix}")
