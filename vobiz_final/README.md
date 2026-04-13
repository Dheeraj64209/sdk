# vobiz2

Monorepo containing:

- `apps/vobiz_demo`: Flutter mobile demo app
- `packages/vobiz_webrtc`: custom Flutter SDK package
- `Vobiz-RTC-demo`: local web demo and XML answer backend
- `_zipinspect/vobiz_flutter`: cleaned Flutter SIP/WebRTC app

## Repository Layout

```text
vobiz2/
├── apps/
│   └── vobiz_demo/
├── packages/
│   └── vobiz_webrtc/
├── Vobiz-RTC-demo/
└── _zipinspect/
    └── vobiz_flutter/
```

## Local Setup Notes

- Do not commit `.env` files or real endpoint credentials.
- Configure caller ID and fallback destinations through environment variables,
  not source code.
- Keep public docs and committed source free of real phone numbers, ngrok URLs,
  and LAN IP addresses.

## Quick Start

### Web Demo / Backend

```powershell
cd C:\path\to\vobiz2\Vobiz-RTC-demo
npm install
npm start
```

Create `Vobiz-RTC-demo/.env` locally with your own values:

```env
CALLER_ID=+<your-caller-id>
DEFAULT_DESTINATION=+<optional-fallback-destination>
```

If you need a public Answer URL for Vobiz, expose port `3000` with ngrok and
use:

```text
https://<your-ngrok-url>/answer
```

### Flutter App

```powershell
cd C:\path\to\vobiz2\_zipinspect\vobiz_flutter
flutter pub get
flutter run --dart-define=VOBIZ_BACKEND_URL=http://127.0.0.1:3000
```

## Before Pushing

- review `git diff`
- make sure `.env` is untracked
- make sure no real numbers, ngrok URLs, or LAN IPs remain in source/docs
