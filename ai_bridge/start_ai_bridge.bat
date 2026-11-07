@echo off
setlocal
cd /d "%~dp0"
py -3 nixo_ai_bridge.py
if errorlevel 1 (
  echo.
  echo Nixo AI bridge stopped. Check the message above and ai_bridge\.env.local
  pause
)
endlocal
