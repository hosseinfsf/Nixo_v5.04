@echo off
setlocal
cd /d "%~dp0"
if not exist "..\bridge\.venv\Scripts\python.exe" (
  echo Creating local Python environment for Control Center…
  python -m venv "..\bridge\.venv"
  if errorlevel 1 goto :fail
)
"..\bridge\.venv\Scripts\python.exe" -m pip install --upgrade pip
"..\bridge\.venv\Scripts\python.exe" -m pip install -r ..\bridge\requirements.txt
if errorlevel 1 goto :fail
echo Starting Nixo Control Center…
"..\bridge\.venv\Scripts\python.exe" control_center.py
pause
exit /b 0
:fail
echo Control Center setup failed. Check Python installation.
pause
exit /b 1
