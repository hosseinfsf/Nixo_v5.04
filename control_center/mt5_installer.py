"""Install and compile the Nixo expert advisor inside a MetaTrader 5 data folder.

The installer copies the packaged MQL5 sources into ``MQL5\\Experts\\Nixo``,
backs up whatever it replaces, then asks MetaEditor to compile from the command
line and reads the compiler log back.
"""
from __future__ import annotations

import os
import shutil
import subprocess
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path

from .paths import MT5_SOURCE_DIR, ROOT, find_terminal_icon

EA_SUFFIXES = (".mq5", ".mqh")
COMPILE_TIMEOUT_SECONDS = 180


@dataclass
class InstallResult:
    ok: bool
    message: str
    target_dir: Path | None = None
    installed: list[Path] = field(default_factory=list)
    backup_dir: Path | None = None
    compiler_log: Path | None = None


def packaged_sources() -> list[Path]:
    """Every MQL5 source shipped in the mt5/ folder."""
    if not MT5_SOURCE_DIR.is_dir():
        return []
    return sorted(
        path for path in MT5_SOURCE_DIR.rglob("*")
        if path.is_file() and path.suffix.lower() in EA_SUFFIXES
    )


def find_metaeditor(data_dir: Path) -> Path | None:
    """Locate metaeditor64.exe next to the terminal that owns this data folder."""
    terminal = find_terminal_icon(data_dir)
    if terminal is not None:
        compiled_editor = terminal.parent / "metaeditor64.exe"
        if compiled_editor.is_file():
            return compiled_editor
    for candidate in (
        Path(os.environ.get("ProgramFiles", r"C:\Program Files")) / "MetaTrader 5" / "metaeditor64.exe",
        Path(os.environ.get("ProgramFiles(x86)", r"C:\Program Files (x86)")) / "MetaTrader 5" / "metaeditor64.exe",
    ):
        if candidate.is_file():
            return candidate
    return None


def experts_dir(data_dir: Path) -> Path:
    return data_dir / "MQL5" / "Experts" / "Nixo"


def _backup(target_dir: Path) -> Path | None:
    """Copy out any files the installer is about to overwrite."""
    if not target_dir.is_dir():
        return None
    existing = [p for p in target_dir.iterdir() if p.is_file()]
    if not existing:
        return None
    stamp = datetime.now().strftime("%Y-%m-%d_%H%M%S")
    backup_dir = ROOT / "mt5" / "backups" / f"{stamp}-installer"
    backup_dir.mkdir(parents=True, exist_ok=True)
    for path in existing:
        shutil.copy2(path, backup_dir / path.name)
    return backup_dir


def read_compiler_log(log_path: Path) -> str | None:
    """MetaEditor writes UTF-16; fall back to UTF-8 if it ever changes."""
    try:
        raw = log_path.read_bytes()
    except OSError:
        return None
    for encoding in ("utf-16", "utf-16-le", "utf-8"):
        try:
            text = raw.decode(encoding)
        except UnicodeError:
            continue
        cleaned = text.replace("\x00", "").strip()
        if cleaned:
            return cleaned
    return None


def log_reports_success(log_text: str) -> bool:
    lowered = log_text.lower()
    if "error" in lowered and "0 error" not in lowered:
        return False
    return "0 error" in lowered or "successful" in lowered


def compile_source(metaeditor: Path, source: Path) -> tuple[bool, str, Path | None]:
    log_path = source.with_suffix(source.suffix + ".log")
    log_path.unlink(missing_ok=True)
    try:
        subprocess.run(
            [str(metaeditor), f"/compile:{source}", f"/log:{log_path}"],
            check=False,
            timeout=COMPILE_TIMEOUT_SECONDS,
            creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0,
        )
    except (OSError, subprocess.SubprocessError) as exc:
        return False, f"MetaEditor could not run: {exc}", None
    text = read_compiler_log(log_path)
    if text is None:
        return False, "MetaEditor produced no compiler log.", log_path
    return log_reports_success(text), text, log_path


def install_ea(data_dir: Path, compile_after: bool = True) -> InstallResult:
    """Copy packaged sources into the terminal and compile the main EA."""
    sources = packaged_sources()
    if not sources:
        return InstallResult(False, "No .mq5 source found in the mt5/ folder.")

    target = experts_dir(data_dir)
    target.mkdir(parents=True, exist_ok=True)
    backup = _backup(target)

    installed: list[Path] = []
    for source in sources:
        destination = target / source.name
        shutil.copy2(source, destination)
        installed.append(destination)

    if not compile_after:
        return InstallResult(
            True,
            f"Copied {len(installed)} source file(s). Compile skipped.",
            target, installed, backup,
        )

    metaeditor = find_metaeditor(data_dir)
    if metaeditor is None:
        return InstallResult(
            False,
            "metaeditor64.exe was not found. Install the EA from MetaEditor with F7.",
            target, installed, backup,
        )

    main_source = next((p for p in installed if p.suffix.lower() == ".mq5"), None)
    if main_source is None:
        return InstallResult(False, "No .mq5 file to compile.", target, installed, backup)

    ok, detail, log_path = compile_source(metaeditor, main_source)
    if ok:
        return InstallResult(
            True, f"Compiled successfully: {main_source.stem}.ex5",
            target, installed, backup, log_path,
        )
    first_error = next(
        (line.strip() for line in detail.splitlines() if "error" in line.lower()),
        detail.splitlines()[0] if detail else "Unknown compiler error",
    )
    return InstallResult(False, f"Compile failed: {first_error}", target, installed, backup, log_path)
