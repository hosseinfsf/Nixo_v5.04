"""Visual tokens and ttk styling for the Nixo Control Center."""
from __future__ import annotations

import tkinter as tk
from tkinter import ttk

BG = "#0B0F14"
SURFACE = "#141B24"
SURFACE_ALT = "#1B242F"
BORDER = "#26303D"
TEXT = "#E8EEF5"
MUTED = "#8A97A6"
ACCENT = "#2FD8A8"
ACCENT_DIM = "#1E6E5C"
DANGER = "#FF5C5C"
WARN = "#F0B429"

FONT = "Segoe UI"
SIZE_TITLE = 30
SIZE_SECTION = 9
SIZE_BODY = 10
SIZE_VALUE = 13


def setup_styles(root: tk.Misc) -> ttk.Style:
    style = ttk.Style(root)
    try:
        style.theme_use("clam")
    except tk.TclError:
        pass

    style.configure(".", background=BG, foreground=TEXT, font=(FONT, SIZE_BODY))
    style.configure("TFrame", background=BG)
    style.configure("TLabel", background=BG, foreground=TEXT, font=(FONT, SIZE_BODY))

    style.configure("Title.TLabel", font=(FONT, SIZE_TITLE, "bold"), foreground=TEXT)
    style.configure("Subtitle.TLabel", font=(FONT, SIZE_BODY), foreground=MUTED)
    style.configure("Section.TLabel", font=(FONT, SIZE_SECTION, "bold"), foreground=MUTED)
    style.configure("Hint.TLabel", font=(FONT, SIZE_BODY), foreground=MUTED)

    style.configure("Panel.TFrame", background=SURFACE)
    style.configure("PanelLabel.TLabel", background=SURFACE, foreground=MUTED,
                    font=(FONT, SIZE_SECTION, "bold"))
    style.configure("PanelValue.TLabel", background=SURFACE, foreground=TEXT,
                    font=(FONT, SIZE_VALUE, "bold"))
    style.configure("PanelDetail.TLabel", background=SURFACE, foreground=MUTED,
                    font=(FONT, 9))

    style.configure("Primary.TButton", font=(FONT, 11, "bold"), padding=(16, 12),
                    background=SURFACE_ALT, foreground=TEXT, borderwidth=0)
    style.map("Primary.TButton",
              background=[("active", BORDER), ("disabled", SURFACE)])
    style.configure("Ghost.TButton", font=(FONT, SIZE_BODY, "bold"), padding=(12, 8),
                    background=SURFACE, foreground=TEXT, borderwidth=0)
    style.map("Ghost.TButton", background=[("active", SURFACE_ALT)])

    style.configure("Treeview", background=SURFACE, fieldbackground=SURFACE,
                    foreground=TEXT, rowheight=26, borderwidth=0)
    style.configure("Treeview.Heading", background=SURFACE_ALT, foreground=MUTED,
                    font=(FONT, 9, "bold"), borderwidth=0)
    style.map("Treeview", background=[("selected", ACCENT_DIM)])

    return style


def state_color(healthy: bool | None) -> str:
    if healthy is None:
        return MUTED
    return ACCENT if healthy else DANGER
