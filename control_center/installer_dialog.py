"""EA install / update dialog backed by the MetaEditor command line compiler."""
from __future__ import annotations

import threading
import tkinter as tk
from pathlib import Path
from tkinter import messagebox, ttk

from . import theme
from .mt5_installer import InstallResult, experts_dir, find_metaeditor, install_ea, packaged_sources
from .paths import terminal_data_dirs


class InstallerDialog(tk.Toplevel):
    """Copies the packaged EA into a terminal and compiles it with F7-equivalent."""

    def __init__(self, master: tk.Misc, on_log=None) -> None:
        super().__init__(master)
        self._on_log = on_log
        self._working = False
        self.title("Nixo · EA installer")
        self.geometry("620x470")
        self.configure(bg=theme.BG)
        self.transient(master.winfo_toplevel())

        body = ttk.Frame(self, padding=22)
        body.pack(fill="both", expand=True)

        ttk.Label(body, text="EXPERT ADVISOR INSTALLER", style="Section.TLabel").pack(anchor="w")
        ttk.Label(
            body,
            text="Copies the packaged .mq5 into MQL5\\Experts\\Nixo, backs up the previous files, then compiles with MetaEditor.",
            style="Hint.TLabel",
            wraplength=560,
            justify="left",
        ).pack(anchor="w", pady=(4, 14))

        terminals = terminal_data_dirs()
        self._folders: dict[str, Path] = {str(path): path for path in terminals}
        ttk.Label(body, text="TERMINAL DATA FOLDER", style="Section.TLabel").pack(anchor="w", pady=(6, 4))
        self._selection = tk.StringVar(value=next(iter(self._folders), ""))
        if self._folders:
            ttk.Combobox(
                body, textvariable=self._selection, values=list(self._folders),
                state="readonly", width=74,
            ).pack(fill="x")
        else:
            ttk.Label(
                body,
                text="No MT5 data folder found. Open MetaTrader 5 once, then reopen this window.",
                style="Hint.TLabel",
            ).pack(anchor="w")

        self._source_label = ttk.Label(
            body,
            text=f"Packaged sources: {len(packaged_sources())} file(s) in mt5/",
            style="Hint.TLabel",
        )
        self._source_label.pack(anchor="w", pady=(14, 0))

        self._output = tk.Text(
            body, height=9, wrap="word", background=theme.SURFACE, foreground=theme.TEXT,
            relief="flat", font=(theme.FONT, 9), padx=10, pady=8,
        )
        self._output.pack(fill="both", expand=True, pady=(12, 0))
        self._output.configure(state="disabled")

        actions = ttk.Frame(body)
        actions.pack(fill="x", pady=(14, 0))
        self._install_button = ttk.Button(
            actions, text="INSTALL / UPDATE NIXO EA", style="Primary.TButton",
            command=self._install,
        )
        self._install_button.pack(side="left")
        self._install_button.configure(state="normal" if self._folders else "disabled")
        ttk.Button(actions, text="CLOSE", style="Ghost.TButton", command=self.destroy).pack(side="right")

        self._write("Ready. Select a terminal and press install.")

    def _write(self, message: str) -> None:
        self._output.configure(state="normal")
        self._output.insert("end", f"{message}\n")
        self._output.see("end")
        self._output.configure(state="disabled")
        if self._on_log is not None:
            self._on_log(message)

    def _install(self) -> None:
        if self._working:
            return
        data_dir = self._folders.get(self._selection.get())
        if data_dir is None:
            messagebox.showerror("No terminal", "Select an MT5 data folder first.", parent=self)
            return
        metaeditor = find_metaeditor(data_dir)
        self._write(f"Installing into {experts_dir(data_dir)}")
        self._write(f"Compiler: {metaeditor}" if metaeditor else "Compiler: not found, copy only")
        self._working = True
        self._install_button.configure(state="disabled")
        threading.Thread(target=self._run, args=(data_dir,), daemon=True).start()

    def _run(self, data_dir: Path) -> None:
        result = install_ea(data_dir)
        self.after(0, lambda: self._finished(result))

    def _finished(self, result: InstallResult) -> None:
        self._working = False
        self._install_button.configure(state="normal")
        if result.backup_dir is not None:
            self._write(f"Backup: {result.backup_dir}")
        self._write(result.message)
        if result.compiler_log is not None:
            self._write(f"Compiler log: {result.compiler_log}")
        if result.ok:
            ex5 = next((p.with_suffix(".ex5") for p in result.installed if p.suffix == ".mq5"), None)
            if ex5 is not None:
                self._write("EX5 present: " + ("yes" if ex5.exists() else "no"))
            messagebox.showinfo(
                "EA installed",
                "Nixo is installed. Remove and re-attach the EA on the chart so the new build takes effect.",
                parent=self,
            )
        else:
            messagebox.showerror("Install failed", result.message, parent=self)
