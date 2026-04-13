# Vobiz Mobile - Flutter WebRTC Calling App

Minimal native Flutter softphone using SIP over WebSocket plus `flutter_webrtc`.
It registers a Vobiz endpoint, places outbound calls through the Vobiz Answer
URL flow, and supports incoming audio calls.

## Stack

- Flutter 3.10+
- `flutter_webrtc`
- `web_socket_channel`
- `crypto`
- `http`

## Project Structure

```text
lib/
├── main.dart
├── client/
│   └── vobiz_client.dart
├── services/
│   ├── backend_service.dart
│   ├── peer_service.dart
│   └── sip_service.dart
├── screens/
│   ├── dialer_screen.dart
│   ├── incall_screen.dart
│   ├── incoming_screen.dart
│   └── login_screen.dart
└── utils/
    └── logger.dart
```

## Configuration

The app supports runtime overrides with `--dart-define`.

```bash
flutter run \
  --dart-define=VOBIZ_BACKEND_URL=http://127.0.0.1:3000 \
  --dart-define=VOBIZ_WS_URL=wss://registrar.vobiz.ai:5063/ \
  --dart-define=VOBIZ_SIP_SERVER=registrar.vobiz.ai
```

If you omit them, the app falls back to the default Vobiz registrar and local
backend URL.

## Setup

1. Start the backend from `Vobiz-RTC-demo`.
2. Expose the backend publicly with ngrok and set the Vobiz Answer URL to
   `https://<ngrok-url>/answer`.
3. Run the Flutter app on a physical device.

## Android USB Example

```bash
adb reverse tcp:3000 tcp:3000
flutter run -d <device-id> --dart-define=VOBIZ_BACKEND_URL=http://127.0.0.1:3000
```

## Notes

- Use a physical device for WebRTC testing.
- The destination number must be different from the configured caller ID.
- Outbound PSTN success still depends on your Vobiz account, caller ID, and
  Answer URL configuration.
