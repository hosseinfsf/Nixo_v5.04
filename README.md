# Nixo X Signal Bridge v2.0

پل اتصال حساب‌های X (توییتر) به اکسپرت Nixo

## قابلیت‌ها

- پشتیبانی از چند حساب همزمان (مدیریت از طریق JSON)
- پارس قوی Rule-based
- لایه هوش مصنوعی رایگان با Groq (برای سیگنال‌های نامنظم)
- نوشتن مستقیم در inbox اکسپرت Nixo
- معماری مشترک (قابل استفاده برای تلگرام و منابع دیگر)

## راه‌اندازی سریع

### ۱. توکن‌ها

فایل `x_bridge/.env.local.example` را کپی کنید و نام آن را بگذارید `.env.local`

محتوای لازم:

```env
X_BEARER_TOKEN=توکن_ایکس_شما
GROQ_API_KEY=کلید_گراک_شما
```

- Bearer Token را از [developer.x.com](https://developer.x.com) بگیرید
- کلید رایگان Groq را از [console.groq.com](https://console.groq.com) بگیرید

### ۲. تنظیم حساب‌ها

فایل `x_bridge/config_x.json` را باز کنید و حساب‌های مورد نظر را اضافه/فعال کنید:

```json
{
  "username": "نام_حساب_بدون_@",
  "enabled": true,
  "allowed_symbols": ["XAUUSD", "GOLD"]
}
```

### ۳. اجرا

فایل `start_x_bridge.bat` را اجرا کنید.

## ساختار

```
Nixo_X_Bridge_Complete/
├── shared/                     ← لایه مشترک پارس (قابل استفاده برای همه منابع)
│   ├── models.py
│   ├── signal_parser.py
│   └── ai_providers/
│       └── groq_free.py
└── x_bridge/
    ├── config_x.json
    ├── x_signal_bridge.py
    ├── start_x_bridge.bat
    ├── requirements.txt
    └── .env.local.example
```

## نکات مهم

- در اولین اجرا فقط پست‌های جدید را پردازش می‌کند (سیگنال‌های قدیمی را نادیده می‌گیرد).
- برای بهترین نتیجه، هم X Bearer Token و هم GROQ_API_KEY را تنظیم کنید.
- اگر مسیر Common Files متاتریدر به صورت خودکار پیدا نشد، آن را در `.env.local` مشخص کنید.
