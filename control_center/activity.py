"""A compact, auto-scrolling activity log widget."""
from __future__ import annotations

import time
import tkinter as tk
from pathlib import Path
from tkinter import ttk

from . import theme

MAX_LINES = 400


class ActivityLog(ttk.Frame):
    """Append-only log panel shared by the whole Control Center."""

    def __init__(self, master: tk.Misc) -> None:
        super().__init__(master, style="Panel.TFrame")
        self._text = tk.Text(
            self,
            height=8,
            wrap="none",
            background=theme.SURFACE,
            foreground=theme.TEXT,
            insertbackground=theme.TEXT,
            selectbackground=theme.ACCENT_DIM,
            relief="flat",
            borderwidth=0,
            font=(theme.FONT, 9),
            padx=10,
            pady=8,
        )
        scrollbar = ttk.Scrollbar(self, orient="vertical", command=self._text.yview)
        self._text.configure(yscrollcommand=scrollbar.set, state="disabled")
        self._text.pack(side="left", fill="both", expand=True)
        scrollbar.pack(side="right", fill="y")
        self._text.tag_configure("time", foreground=theme.MUTED)
        self._text.tag_configure("good", foreground=theme.ACCENT)
        self._text.tag_configure("bad", foreground=theme.DANGER)
        self._text.tag_configure("warn", foreground=theme.WARN)

    def append(self, message: str, level: str = "info") -> None:
        stamp = time.strftime("%H:%M:%S")
        self._text.configure(state="normal")
        self._text.insert("end", f"{stamp}  ", ("time",))
        self._text.insert("end", f"{message}\n", (level,) if level in {"good", "bad", "warn"} else ())
        self._trim()
        self._text.configure(state="disabled")
        self._text.see("end")

    def _trim(self) -> None:
        line_count = int(self._text.index("end-1c").split(".")[0])
        if line_count > MAX_LINES:
            self._text.delete("1.0", f"{line_count - MAX_LINES}.0")

    def tail(self, path: Path, count: int = 6) -> list[str]:
        """Return the last meaningful lines of a helper log, if it exists."""
        try:
            raw = path.read_text(encoding="utf-8", errors="replace").splitlines()
        except OSError:
            return []
        lines = [line.strip() for line in raw if line.strip()]
        return lines[-count:]
