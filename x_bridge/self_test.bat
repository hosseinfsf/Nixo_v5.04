@echo off
cd /d "%~dp0"
py -3 signal_bridge.py --self-test
pause
