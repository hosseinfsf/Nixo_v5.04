# Nixo v5.04 — Demo-Safe Checklist (Telegram → MT5 Control Center)

این چک‌لیست برای عبور ایمن از Paper → Live روی حساب **Demo** در مسیر تلگرام → متاتریدر است. هرگز روی حساب Real نروید تا soaked-test کامل نکرده باشید.

## ۱) محیط و دسترسی‌ها
- [ ] ویندوز + MetaTrader 5 دسکتاپ نصب و فعال است.
- [ ] اکسپرت `mt5/Nixo_v5.04_TradingModes_AdvancedAnalytics.mq5` در `MQL5/Experts` کپی شده و با **F7** کامپイル شده است (خطای کامپایل نیست).
- [ ] اکسپرت روی نمودار نماد سیگنال (مثلاً XAUUSD یا طلای با پسوند بروکر) نصب شده و **Algo Trading** روشن است.
- [ ] حساب **Demo** از نوع **Hedging** است (کپی زنده سیگنال نیازمند Hedging است).
- [ ] Python 3.10+ و محیط `bridge/.venv` (Telethon) آماده است.

## ۲) насел‌های سیگنال (Control Center)
- [ ] `control_center/start_control_center.bat` اجرا شده و پنل باز می‌شود.
- [ ] `.env.local` در پوشه `bridge` ساخته شده و `TELEGRAM_API_ID` / `TELEGRAM_API_HASH` پر شده است (فایل اصلاً commit نمی‌شود).
- [ ] از طریق Control Center → **Telegram Login** وارد حساب تلگرامی شده‌اید و فایل `nixo_telegram.session` ساخته شده است.
- [ ] از طریق **Source Manager** کانال/کانال‌های سیگنال اضافه شده‌اند (username کانال، نماد‌های مجاز مثل XAUUSD).
- [ ] هر منبع togglebale است (ON/OFF مجزا) و تغییرات در `config/sources.json` ثبت می‌شوند.
- [ ] Bridge (`bridge/start_bridge.bat`) در حال اجرا است و log `Listening Telegram` را نشان می‌دهد.
- [ ] فایل‌های `.sig` در `Common\Files\NixoBridge\inbox` می‌آیند (مسیر `MT5_COMMON_FILES` در `.env.local` اگر اشتباه است، اصلاح شده است).

## ۳) Control Center —Master Gate
- [ ] دکمه **MASTER OFF** حالت پیش‌فرض است (contro.json master_armed=false).
- [ ] با زدن **MASTER ON**، `control.json` نوشته می‌شود و intake سیگنال فعال می‌شود.
- [ ] با زدن **MASTER OFF**، هیچ **ORD** جدیدی از طریق تلگرام ثبت نمی‌شود (پوزیشن/سفارش معلق موجود دست‌نخورده می‌ماند).
- [ ] Health panel نشان می‌دهد ea_status heartbeat تازه است و trade_mode=DEMO.

## ۴) EA — Security Gates (Internal)
- [ ] `InpSignalLabEnabled = true` باشد.
- [ ] `InpSignalLiveAllowed = false` در مرحلة آزمایش Paper بماند.
- [ ] Trading Mode روی **EXTERNAL SIGNALS** تنظیم شده باشد قبل از ARM کردن Signal Live.
- [ ] دکمه **SIGNAL LIVE** در پنل EA فقط بعد از فعال بودن `InpSignalLiveAllowed` و انتخاب EXTERNAL mode کار کند.
- [ ] `ControlGateAllowsLive()` در EA قبل از هر سفارش live بررسی می‌کند: master armed، heartbeat تازه، حساب Demo.
- [ ] هر `event_uid` (signalId) فقط یک بار پردازش شود (SEEN/Dedup)؛ تکرار پیام را نادیده بگیرد.

## ۵) Paper → Live على Demo
- [ ] حداقل ۵–۱۰ سیگنال تلگرام واقعی در **Paper Lab** بررسی شده و periodista/تکرار نشده‌اند.
- [ ] SL/TPها در Journal و با قیمت‌های سیگنال مطابقت دارند.
- [ ] روی حساب Demo Hedging، `InpSignalLiveAllowed` را `true` کنید، اکسپرت را Reload کنید و **SIGNAL LIVE** را بزنید.
- [ ] اولین سفارش live روی اندکی حجم (مثلاً ۰.۰۱ لات) باشد و纯اً آزمایشی.
- [ ] after first live fill, verify roulette state (order-step / volume-step) tracked per `source_id`.

## ۶)禁止项 (Never)
- [ ] هرگز `.env.local`، `*.session`، API HASH یا کد ورود تلگرام را commit یا برای کسی ارسال نکنید.
- [ ] هرگز روی حساب Real کپی زنده را قبل از soaked-test روی Demo فعال نکنید.
- [ ] هرگز `.ex5` را دستی تغییر نکنید؛ همیشه از `.mq5` کامپایل کنید.

## ۷) 끝난 / Rollback
- [ ] **MASTER OFF** در Control Center ↔ intake تلگرام متوقف می‌شود.
- [ ] **SIGNAL LIVE** در پنل EA ↔ کپی زنده متوقف می‌شود (Paper Lab همچنان کار می‌کند).
- [ ] **CLOSE NIXO POSITIONS ONLY** ↔ پوزیشن‌های Nixo/سیگنال بسته می‌شوند؛ سفارش‌های معلق حفظ می‌شوند.
