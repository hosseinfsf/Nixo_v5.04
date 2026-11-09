@echo off
chcp 65001 >nul
cd /d "%~dp0"

echo ========================================
echo   Nixo X Signal Bridge v2.0
echo   Rule-based + Groq AI
echo ========================================
echo.

if not exist ".env.local" (
    echo [ERROR] فایل .env.local پیدا نشد!
    echo.
    echo 1. فایل .env.local.example را کپی کنید
    echo 2. اسم آن را به .env.local تغییر دهید
    echo 3. توکن‌های X و Groq را داخلش بگذارید
    echo.
    pause
    exit /b 1
)

echo نصب وابستگی‌ها...
python -m pip install -r requirements.txt -q

echo.
echo شروع Bridge...
echo.
python x_signal_bridge.py

pause
