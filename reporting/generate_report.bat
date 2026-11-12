@echo off
setlocal
cd /d "%~dp0"
set "COMMON=%APPDATA%\MetaQuotes\Terminal\Common\Files\NixoReports"
if not exist "%COMMON%" (
  echo NixoReports folder not found: "%COMMON%"
  echo First press ADVANCED REPORT in the Nixo panel.
  pause
  exit /b 1
)
for /f "delims=" %%F in ('dir /b /a-d /o-d "%COMMON%\Nixo_Deals_*.csv" 2^>nul') do (set "LATEST=%%F" & goto :found)
:found
if not defined LATEST (echo No Nixo deal export found.& pause & exit /b 1)
echo Generating report from %LATEST%
py -3 nixo_report.py --input "%COMMON%\%LATEST%"
if errorlevel 1 (echo Report generation failed.& pause & exit /b 1)
start "" "%COMMON%\Nixo_Analytics_Report.html"
echo Done.
