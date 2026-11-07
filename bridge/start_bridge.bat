@echo off
setlocal
cd /d "%~dp0"
if not exist ".env.local" (
  echo No .env.local found.
  echo RSS/Atom-only sources can run without it; Telegram sources need credentials.
  echo Copy .env.local.example to .env.local and fill Telegram credentials when needed.
  echo.
)
if not exist ".venv\Scripts\python.exe" (
  py -3 -m venv .venv
  if errorlevel 1 goto :fail
)
".venv\Scripts\python.exe" -m pip install --upgrade pip
".venv\Scripts\python.exe" -m pip install -r requirements.txt
if errorlevel 1 goto :fail
".venv\Scripts\python.exe" signal_bridge.py
pause
exit /b 0
:fail
echo Bridge setup failed. Check Python installation and internet access for pip.
pause
exit /b 1
