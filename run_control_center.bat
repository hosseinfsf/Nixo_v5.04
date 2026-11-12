@echo off
setlocal
set "ROOT=%~dp0"
if not exist "%ROOT%bridge\.venv\Scripts\python.exe" (
  echo Python environment not found. Running setup first...
  call "%ROOT%setup_bridge.bat"
  if errorlevel 1 exit /b 1
)
"%ROOT%bridge\.venv\Scripts\python.exe" "%ROOT%control_center\nixo_control_center.py"
if errorlevel 1 (
  echo.
  echo Control Center exited with an error. Check Python/Tkinter and the project files.
  pause
)
