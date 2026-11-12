"""Tkinter source add / manage wizard for the Nixo Control Center."""
from __future__ import annotations

import json
import re
import tkinter as tk
from pathlib import Path
from tkinter import messagebox, simpledialog, ttk
from urllib.parse import urlparse


def _source_id(value: str) -> str:
    return re.sub(r"[^a-zA-Z0-9_-]+", "_", value.strip().lstrip("@"))[:32] or "source"


def _parse_symbols(raw: str) -> list[str]:
    values = [x.strip().upper() for x in raw.split(",") if x.strip()]
    return list(dict.fromkeys(values))


class SourceWizard(tk.Toplevel):
    def __init__(self, parent, config_path: Path, sources: list[dict], mode: str = "add"):
        super().__init__(parent)
        self.config_path = config_path
        self.sources = sources
        self.mode = mode  # "add" or "manage"
        self.result = None
        self.title("Source Manager" if mode == "manage" else "Add Signal Source")
        self.geometry("640x420")
        self.transient(parent)
        self.grab_set()
        self._build_ui()
        self._refresh_list()

    def _build_ui(self) -> None:
        pad = {"padx": 10, "pady": 6}

        top = ttk.Frame(self)
        top.pack(fill=tk.BOTH, expand=True, **pad)

        if self.mode == "manage":
            self.listbox = tk.Listbox(top, height=10)
            self.listbox.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
            scroll = ttk.Scrollbar(top, orient=tk.VERTICAL, command=self.listbox.yview)
            scroll.pack(side=tk.LEFT, fill=tk.Y)
            self.listbox.configure(yscrollcommand=scroll.set)

            btns = ttk.Frame(self)
            btns.pack(fill=tk.X, **pad)
            ttk.Button(btns, text="Edit selected", command=self.edit_selected).pack(side=tk.LEFT)
            ttk.Button(btns, text="Toggle enabled", command=self.toggle_selected).pack(side=tk.LEFT, padx=6)
            ttk.Button(btns, text="Remove selected", command=self.remove_selected).pack(side=tk.LEFT, padx=6)
            ttk.Button(btns, text="Close", command=self.close_manage).pack(side=tk.RIGHT)
        else:
            form = ttk.Frame(top)
            form.pack(fill=tk.BOTH, expand=True)

            ttk.Label(form, text="Source type:").grid(row=0, column=0, sticky=tk.W, pady=4)
            self.type_var = tk.StringVar(value="telegram")
            ttk.Radiobutton(form, text="Telegram channel", variable=self.type_var, value="telegram").grid(
                row=0, column=1, sticky=tk.W)
            ttk.Radiobutton(form, text="RSS / Atom feed", variable=self.type_var, value="rss").grid(
                row=0, column=2, sticky=tk.W, padx=10)

            ttk.Label(form, text="Display name:").grid(row=1, column=0, sticky=tk.W, pady=4)
            self.name_entry = ttk.Entry(form, width=40)
            self.name_entry.grid(row=1, column=1, columnspan=2, sticky=tk.W, pady=4)

            ttk.Label(form, text="Channel @username or feed URL:").grid(row=2, column=0, sticky=tk.W, pady=4)
            self.endpoint_entry = ttk.Entry(form, width=40)
            self.endpoint_entry.grid(row=2, column=1, columnspan=2, sticky=tk.W, pady=4)

            ttk.Label(form, text="Source ID (unique):").grid(row=3, column=0, sticky=tk.W, pady=4)
            self.id_entry = ttk.Entry(form, width=40)
            self.id_entry.grid(row=3, column=1, columnspan=2, sticky=tk.W, pady=4)

            ttk.Label(form, text="Allowed symbols (comma-separated, e.g. XAUUSD):").grid(
                row=4, column=0, sticky=tk.W, pady=4)
            self.symbols_entry = ttk.Entry(form, width=40)
            self.symbols_entry.insert(0, "XAUUSD")
            self.symbols_entry.grid(row=4, column=1, columnspan=2, sticky=tk.W, pady=4)

            self.single_var = tk.BooleanVar(value=False)
            ttk.Checkbutton(
                form, text="Assume this source's only symbol if ticker is omitted",
                variable=self.single_var,
            ).grid(row=5, column=1, columnspan=2, sticky=tk.W, pady=4)

            self.enabled_var = tk.BooleanVar(value=True)
            ttk.Checkbutton(form, text="Enable this source now", variable=self.enabled_var).grid(
                row=6, column=1, columnspan=2, sticky=tk.W, pady=4)

            act = ttk.Frame(self)
            act.pack(fill=tk.X, **pad)
            ttk.Button(act, text="Save", command=self.save_add).pack(side=tk.LEFT)
            ttk.Button(act, text="Cancel", command=self.close_add).pack(side=tk.LEFT, padx=6)

    # ------------------------------------------------------------------ manage mode
    def _refresh_list(self) -> None:
        if self.mode != "manage":
            return
        self.listbox.delete(0, tk.END)
        for s in self.sources:
            st = str(s.get("source_type", "telegram")).upper()
            ep = s.get("channel") or s.get("feed_url", "")
            flag = "ON " if s.get("enabled") else "OFF"
            self.listbox.insert(tk.END, f"{flag} [{st}] {s.get('name')} | {ep} | id={s.get('id')}")

    def _selected_index(self) -> int | None:
        sel = self.listbox.curselection()
        return sel[0] if sel else None

    def edit_selected(self) -> None:
        idx = self._selected_index()
        if idx is None:
            messagebox.showinfo("Edit source", "Select a source row first.")
            return
        src = self.sources[idx]
        st = str(src.get("source_type", "telegram")).lower()
        name = simpledialog.askstring("Edit name", "Display name:", initialvalue=src.get("name", ""), parent=self)
        if name is None:
            return
        src["name"] = name or src.get("id", "")
        if st == "telegram":
            val = simpledialog.askstring("Edit channel", "Channel @username:", initialvalue=src.get("channel", ""), parent=self)
            if val is not None:
                val = val.lstrip("@")
                if val and re.fullmatch(r"[A-Za-z0-9_]{3,}", val):
                    src["channel"] = val
                else:
                    messagebox.showwarning("Invalid", "Invalid Telegram channel username; keeping previous value.")
        else:
            val = simpledialog.askstring("Edit feed URL", "RSS/Atom URL:", initialvalue=src.get("feed_url", ""), parent=self)
            if val is not None:
                parsed = urlparse(val)
                if parsed.scheme in {"http", "https"} and parsed.netloc:
                    src["feed_url"] = val
                else:
                    messagebox.showwarning("Invalid", "Invalid URL; keeping previous feed URL.")
        sym = simpledialog.askstring("Edit symbols", "Allowed symbols:", initialvalue=",".join(src.get("allowed_symbols", [])), parent=self)
        if sym is not None:
            src["allowed_symbols"] = _parse_symbols(sym) or ["XAUUSD"]
        src["enabled"] = messagebox.askyesno("Enable source?", "Enable this source?", parent=self)
        src["assume_single_symbol"] = messagebox.askyesno(
            "Assume single symbol?", "Assume the only allowed symbol when ticker is omitted?", parent=self,
        )
        self._refresh_list()

    def toggle_selected(self) -> None:
        idx = self._selected_index()
        if idx is None:
            messagebox.showinfo("Toggle", "Select a source row first.")
            return
        src = self.sources[idx]
        src["enabled"] = not bool(src.get("enabled"))
        self._refresh_list()

    def remove_selected(self) -> None:
        idx = self._selected_index()
        if idx is None:
            messagebox.showinfo("Remove", "Select a source row first.")
            return
        src = self.sources[idx]
        if not messagebox.askyesno("Remove source", f"Remove '{src.get('name', src.get('id'))}'?", parent=self):
            return
        self.sources.pop(idx)
        self._refresh_list()

    def close_manage(self) -> None:
        self.result = self.sources
        self.destroy()

    # ------------------------------------------------------------------ add mode
    def save_add(self) -> None:
        st = self.type_var.get()
        name = self.name_entry.get().strip()
        endpoint = self.endpoint_entry.get().strip()
        sid = self.id_entry.get().strip() or _source_id(endpoint.split("/")[-1])
        symbols = self.symbols_entry.get().strip() or "XAUUSD"

        if st == "telegram":
            endpoint = endpoint.lstrip("@")
            if not endpoint or not re.fullmatch(r"[A-Za-z0-9_]{3,}", endpoint):
                messagebox.showwarning("Invalid", "Invalid Telegram channel username.")
                return
        else:
            parsed = urlparse(endpoint)
            if parsed.scheme not in {"http", "https"} or not parsed.netloc:
                messagebox.showwarning("Invalid", "Feed URL must be a valid http(s) RSS/Atom URL.")
                return

        if any(str(s.get("id", "")) == sid for s in self.sources):
            messagebox.showwarning("Duplicate", "That source ID already exists.")
            return

        item = {
            "id": sid,
            "name": name or sid,
            "source_type": st,
            "enabled": bool(self.enabled_var.get()),
            "parser": "standard",
            "allowed_symbols": _parse_symbols(symbols),
            "assume_single_symbol": bool(self.single_var.get()),
        }
        if st == "telegram":
            item["channel"] = endpoint
        else:
            item["feed_url"] = endpoint
            item["poll_seconds"] = 45
        self.result = item
        self.destroy()

    def close_add(self) -> None:
        self.result = None
        self.destroy()
