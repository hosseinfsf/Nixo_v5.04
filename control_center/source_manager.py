"""Telegram source management dialog."""
from __future__ import annotations

import tkinter as tk
from tkinter import messagebox, ttk

from . import theme
from .source_form import SourceForm
from .sources_store import (
    SourceError,
    load_config,
    remove,
    set_enabled,
    telegram_sources,
    upsert_telegram,
)

COLUMNS = (
    ("name", "SOURCE", 190),
    ("channel", "CHANNEL", 170),
    ("symbols", "SYMBOLS", 160),
    ("state", "STATE", 70),
)


class SourceManager(tk.Toplevel):
    """Lists, edits, enables, and removes Telegram signal sources."""

    def __init__(self, master: tk.Misc, on_change=None) -> None:
        super().__init__(master)
        self._on_change = on_change
        self.title("Nixo · Telegram sources")
        self.geometry("740x430")
        self.minsize(680, 380)
        self.configure(bg=theme.BG)
        self.transient(master.winfo_toplevel())

        header = ttk.Frame(self, padding=(20, 18, 20, 8))
        header.pack(fill="x")
        ttk.Label(header, text="TELEGRAM SOURCE MANAGER", style="Section.TLabel").pack(anchor="w")
        ttk.Label(
            header,
            text="Each channel can be switched off independently. Changes apply the next time the system is turned on.",
            style="Hint.TLabel",
        ).pack(anchor="w", pady=(4, 0))

        table = ttk.Frame(self, padding=(20, 4))
        table.pack(fill="both", expand=True)
        self.tree = ttk.Treeview(
            table, columns=[c[0] for c in COLUMNS], show="headings", selectmode="browse"
        )
        for key, title, width in COLUMNS:
            self.tree.heading(key, text=title)
            self.tree.column(key, width=width, anchor="w")
        self.tree.pack(side="left", fill="both", expand=True)
        scrollbar = ttk.Scrollbar(table, orient="vertical", command=self.tree.yview)
        self.tree.configure(yscrollcommand=scrollbar.set)
        scrollbar.pack(side="right", fill="y")
        self.tree.tag_configure("off", foreground=theme.MUTED)
        self.tree.bind("<Double-1>", lambda _event: self._edit())

        actions = ttk.Frame(self, padding=(20, 12, 20, 18))
        actions.pack(fill="x")
        ttk.Button(actions, text="ADD CHANNEL", style="Primary.TButton", command=self._add).pack(side="left")
        for label, handler in (
            ("EDIT", self._edit),
            ("ON / OFF", self._toggle),
            ("REMOVE", self._remove),
        ):
            ttk.Button(actions, text=label, style="Ghost.TButton", command=handler).pack(
                side="left", padx=(8, 0)
            )
        ttk.Button(actions, text="CLOSE", style="Ghost.TButton", command=self.destroy).pack(side="right")

        self._reload()

    def _reload(self) -> None:
        self.tree.delete(*self.tree.get_children())
        try:
            sources = telegram_sources(load_config())
        except SourceError as exc:
            messagebox.showerror("Could not load sources", str(exc), parent=self)
            return
        for source in sources:
            self.tree.insert(
                "",
                "end",
                iid=str(source.get("id", "")),
                values=(
                    source.get("name", ""),
                    f"@{source.get('channel', source.get('channel_id', ''))}",
                    ", ".join(source.get("allowed_symbols", [])),
                    "ON" if source.get("enabled") else "OFF",
                ),
                tags=() if source.get("enabled") else ("off",),
            )
        if self._on_change is not None:
            self._on_change()

    def _selected(self) -> dict | None:
        selection = self.tree.selection()
        if not selection:
            messagebox.showinfo("Select a channel", "Choose a Telegram source first.", parent=self)
            return None
        source_id = selection[0]
        return next(
            (item for item in telegram_sources(load_config()) if str(item.get("id")) == source_id),
            None,
        )

    def _add(self) -> None:
        form = SourceForm(self)
        self.wait_window(form)
        if form.result:
            self._persist(form.result, existing_id=None)

    def _edit(self) -> None:
        source = self._selected()
        if source is None:
            return
        form = SourceForm(self, source)
        self.wait_window(form)
        if form.result:
            self._persist(form.result, existing_id=str(source["id"]))

    def _persist(self, values: dict, existing_id: str | None) -> None:
        try:
            data = load_config()
            upsert_telegram(
                data,
                name=values["name"],
                channel=values["channel"],
                symbols=values["symbols"],
                enabled=values["enabled"],
                assume_single_symbol=values["assume_single_symbol"],
                existing_id=existing_id,
            )
        except SourceError as exc:
            messagebox.showerror("Could not save source", str(exc), parent=self)
            return
        self._reload()

    def _toggle(self) -> None:
        source = self._selected()
        if source is None:
            return
        try:
            set_enabled(str(source["id"]), not bool(source.get("enabled")))
        except SourceError as exc:
            messagebox.showerror("Could not update source", str(exc), parent=self)
            return
        self._reload()

    def _remove(self) -> None:
        source = self._selected()
        if source is None:
            return
        if not messagebox.askyesno(
            "Remove source", f"Remove '{source.get('name', source.get('id'))}'?", parent=self
        ):
            return
        try:
            remove(str(source["id"]))
        except SourceError as exc:
            messagebox.showerror("Could not remove source", str(exc), parent=self)
            return
        self._reload()
