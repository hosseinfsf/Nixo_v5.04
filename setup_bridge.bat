@echo off
setlocal
set "ROOT=%~dp0"
cd /d "%ROOT%bridge"
if not exist ".venv\Scripts\python.exe" (
  echo [1/3] Creating bridge Python environment...
  py -3 -m venv .venv
  if errorlevel 1 goto :fail
)
echo [2/3] Updating pip...
".venv\Scripts\python.exe" -m pip install --upgrade pip
if errorlevel 1 goto :fail
echo [3/3] Installing Telegram bridge requirements...
".venv\Scripts\python.exe" -m pip install -r requirements.txt
if errorlevel 1 goto :fail
if not exist ".env.local" (
  copy ".env.local.example" ".env.local" >nul
  echo.
  echo Created bridge\.env.local from the example.
  echo Open it and fill TELEGRAM_API_ID and TELEGRAM_API_HASH before starting Nixo.
)
echo.
echo Setup completed. Now run run_control_center.bat from the project root.
pause
exit /b 0
:fail
echo.
echo Setup failed. Check Python 3 and internet access, then run this file again.
pause
exit /b 1
