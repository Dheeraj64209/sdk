# Vobiz Flutter Mobile App — Implementation Guide

## ✅ What's Been Implemented

### Core Features
1. **SIP Registration** — Full Vobiz endpoint registration with MD5 digest auth
2. **Outbound Calls** — Dial any number, WebRTC peer connection, SIP INVITE to carrier
3. **Inbound Calls** — Receive calls, show caller ID, Accept/Reject
4. **WebRTC Audio** — flutter_webrtc audio streaming with STUN servers
5. **Backend Integration** — Node.js backend bridge for call routing
6. **Full State Management** — StreamBuilder-based reactive UI
7. **Error Handling** — Friendly error messages, timeout protection

### Architecture Improvements Made
✅ **Call Flow Completion** — `vobiz_client.dart:143-181`
   - Creates WebRTC peer + offer
   - Sends destination to Node backend
   - **Sends SIP INVITE to Vobiz** (this was missing, now fixed)

✅ **Backend Service Robustness** — `backend_service.dart`
   - Added 10-second timeout protection
   - Proper error logging with Log.* utilities
   - HTTP status validation

✅ **Dialer UI Cleanup** — `dialer_screen.dart`
   - Removed debug code
   - Added empty field validation with SnackBar
   - Async call handling

---

## 🚀 Quick Start

### Prerequisites
- **Flutter 3.10+** installed
- **Physical device** (Android/iOS) for testing
- **Node.js** running the backend on `http://192.168.1.12:3000`
- **Vobiz account** with endpoint credentials
- **WiFi** (phone + backend on same network)

### Step 1: Setup Vobiz Credentials

1. Go to [Vobiz Console](https://console.vobiz.ai)
2. Navigate to **Voice > Endpoints**
3. Create or select an endpoint
4. Copy **Username** and **Password**

### Step 2: Start the Node Backend

```bash
cd Vobiz-RTC-demo
npm install
npm start
```

Your backend will run on `http://192.168.1.12:3000`

### Step 3: Run the Flutter App

```bash
cd _zipinspect/vobiz_flutter
flutter pub get
flutter run -d <device-id>
```

To see available devices: `flutter devices`

---

## 📞 Call Flow (How It Works)

### Outbound Call Flow

```
┌─────────────┐
│  User taps  │
│  "Call"     │ → Phone number: +1234567890
└──────┬──────┘
       │
       ▼
┌──────────────────────────────────────┐
│ vobiz_client.dart → call()          │
└──────────────────────────────────────┘
       │
       │ 1. Create WebRTC peer connection
       ▼
       ├─→ PeerService.createPeerConnection()
       │
       │ 2. Get local audio + create offer SDP
       ▼
       ├─→ PeerService.attachLocalAudioStream()
       ├─→ PeerService.createOffer() → Returns SDP
       │
       │ 3. Tell backend the dialed number
       ▼
       ├─→ BackendService.makeCall("+1234567890")
       │   │ POST http://192.168.1.12:3000/call
       │   │ {"to": "+1234567890"}
       │   └─→ Backend stores in `lastDialedNumber`
       │
       │ 4. Send SIP INVITE with offer to Vobiz
       ▼
       └─→ SIPService.call(destination, sdp)
          │ Sends SIP INVITE to registrar.vobiz.ai:5063
          │ Includes offer SDP + backend will provide Answer URL
          │
          ▼
        State: CallState.calling
        │
        │ Wait for Vobiz response...
        │
        ├─ 180 Ringing → onRemoteRinging → CallState.ringing
        │
        ├─ 200 OK → onCallAnswered
        │  │ Apply remote answer SDP
        │  │ Send ACK
        │  ▼
        │  CallState.inCall ← Call established!
        │
        └─ Error → Show error message, back to idle
```

### Backend Integration at Vobiz Server

When Vobiz receives the INVITE, it queries the Answer URL:

```
┌────────────────────────────────────────┐
│ Vobiz receives INVITE with SDP         │
│ from Flutter + your endpoint username   │
└────────────────────┬───────────────────┘
                     │
                     │ Query Answer URL
                     ▼
        ┌─────────────────────────┐
        │ Node Backend            │
        │ http://192.168.1.12:3000│
        │ (via ngrok for internet)│
        └────────────┬────────────┘
                     │
                     │ Checks: lastDialedNumber = "+1234567890"
                     │ (stored from Flutter's /call request)
                     │
                     ▼
        ┌─────────────────────────────────────────────┐
        │ Returns XML:                                │
        │ <Response>                                  │
        │   <Dial callerId="+918046733542">          │
        │     <Number>+1234567890</Number>           │
        │   </Dial>                                   │
        │ </Response>                                 │
        └────────────┬────────────────────────────────┘
                     │
                     ▼
        ┌──────────────────────────────────────────────┐
        │ Vobiz bridges call to PSTN/PBX              │
        │ Destination phone rings                      │
        │ When answered: voice path established        │
        └──────────────────────────────────────────────┘
```

### Inbound Call Flow

```
┌─────────────────────────────┐
│ Vobiz receives SIP INVITE   │
│ (someone calling your endpoint)
└────────────┬────────────────┘
             │
             │ onIncomingCall callback
             ▼
    ┌────────────────────┐
    │ IncomingScreen     │
    │ Shows caller ID    │
    │ "John Smith"       │
    └──────┬─────────────┘
           │
           ├─ User taps "Accept" → client.answer()
           │  │ Create answer SDP from stored offer
           │  │ Send 200 OK with answer SDP
           │  │ Wait for ACK
           │  ▼
           │  CallState.inCall
           │
           └─ User taps "Reject" → client.reject()
              │ Send 486 Busy Here
              │ Back to idle
              ▼
         CallState.idle
```

---

## 🔧 Configuration

### Vobiz SIP Server
**File:** `lib/main.dart:122-125`

```dart
final client = VobizClient(
  wsUrl:     'wss://registrar.vobiz.ai:5063/',
  sipServer: 'registrar.vobiz.ai',
);
```

### Node Backend
**File:** `lib/services/backend_service.dart:6`

```dart
static const String baseUrl = "http://192.168.1.12:3000";
```

Make sure your **Flutter device can reach this IP** on WiFi.

### Vobiz Answer URL (for production)
In [Vobiz Console](https://console.vobiz.ai):
1. **Voice > Applications**
2. Create/Edit application
3. Set **Answer URL** to: `https://<your-ngrok-url>/`
4. Link your phone number or endpoint to this application

Example ngrok command:
```bash
ngrok http 3000
# Returns: https://abc123.ngrok.io
```

---

## 📊 State Diagram

```
       DISCONNECTED
            │
            │ login(username, password)
            ▼
       CONNECTING
            │
            │ WebSocket connected
            ▼
       CONNECTED → REGISTERING
            │           │
            │           │ 200 OK
            │           ▼
            │       REGISTERED ◄─── Registration refresh (every 55 min)
            │           │
            │           ├─ call(number)
            │           │  ├─ CALLING
            │           │  │  ├─ 180 Ringing → RINGING
            │           │  │  │  └─ 200 OK → IN_CALL
            │           │  │  └─ Error → IDLE
            │           │
            │           ├─ onIncomingCall
            │           │  ├─ INCOMING
            │           │  │  ├─ user.answer() → RINGING → IN_CALL
            │           │  │  └─ user.reject() → IDLE
            │           │
            │           └─ disconnect()
            │              ▼
            └──────────► IDLE
```

---

## 🧪 Testing Checklist

### Local Testing (on WiFi)

- [ ] **Login Test**
  - Enter Vobiz endpoint username/password
  - Should see "Registered" status
  - Check backend logs for `/call` request

- [ ] **Outbound Call Test**
  - Dial test number (e.g., +1234567890)
  - Should see "Calling..." → "Ringing..." → "In Call"
  - Audio should flow if destination answers
  - Click "End Call" → Back to dialer
  - Check backend logs show Answer URL request

- [ ] **Incoming Call Test**
  - Call your endpoint from another phone/SIP client
  - Should see incoming call screen with caller ID
  - Tap "Accept" → should transition to "In Call"
  - Audio should work
  - Click "End Call" → Back to dialer

- [ ] **Error Handling**
  - Try calling while disconnected → Should show error
  - Call with invalid number → Vobiz should reject with error
  - Kill backend API → Should timeout after 10 seconds
  - Network down → Should show connection error

### Production Testing (with ngrok)

1. **Expose backend to internet:**
   ```bash
   ngrok http 3000
   ```

2. **Update Vobiz Dashboard:**
   - Set Answer URL to your ngrok URL

3. **Test from public PSTN:**
   - Dial your Vobiz phone number
   - Should see incoming call on app
   - Accept and talk

---

## 📱 Platform-Specific Setup

### Android

**File:** `android/app/src/main/AndroidManifest.xml`

Make sure inside `<manifest>` tag:

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
```

### iOS

**File:** `ios/Runner/Info.plist`

Make sure inside `<dict>` tag:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>Required for voice calls</string>
<key>NSLocalNetworkUsageDescription</key>
<string>Required to connect to local backend server</string>
<key>NSBonjourServices</key>
<array>
  <string>_http._tcp</string>
  <string>_https._tcp</string>
</array>
```

---

## 🔍 Debugging

### View Logs

```bash
# Terminal 1: Run Flutter app with logs
flutter run -d <device-id>

# Terminal 2: View device logs
flutter logs
```

You'll see logs tagged with:
- `[Client]` — App state transitions
- `[SIP]` — SIP protocol events
- `[WebRTC]` — Peer connection state
- `[Backend]` — HTTP requests

### Monitor Backend

```bash
# Terminal: Watch Node.js logs
npm start

# You should see:
# 📞 Call requested from Flutter → +1234567890
# ✅ XML returned → Dialing: +1234567890
```

### Check Vobiz Dashboard

1. Go to [Vobiz Console](https://console.vobiz.ai)
2. **Voice > Call Logs**
3. Look for your test calls
4. Verify SIP messages are being exchanged

---

## 🐛 Troubleshooting

### "Registration failed (403 Forbidden)"
**Cause:** Wrong username or password
**Fix:** Check credentials in Vobiz Console > Endpoints

### "Call setup failed: No microphone found"
**Cause:** Phone doesn't have microphone permission
**Fix:** Check Settings > Apps > Vobiz > Permissions

### "Backend request timed out"
**Cause:** Can't reach `192.168.1.12:3000`
**Fix:**
- Make sure Node backend is running
- Check phone is on same WiFi as backend
- Change IP if your network is different

### "Calling... but never rings"
**Cause:** Answer URL not configured in Vobiz
**Fix:**
- Go to Vobiz Console > Voice > Applications
- Set Answer URL to your ngrok URL
- Link phone number to application

### "No audio during call"
**Cause:** WebRTC not connecting or ICE candidates not flowing
**Fix:**
- Use physical device (not emulator)
- Check STUN servers are reachable
- Check microphone permission is granted
- Look for "ICE gathering timeout" in logs (acceptable, proceeds with partial candidates)

---

## 📚 Project Structure

```
_zipinspect/vobiz_flutter/
├── lib/
│   ├── main.dart                    # App entry point + routing
│   ├── client/
│   │   └── vobiz_client.dart       # Central controller (state machine)
│   ├── services/
│   │   ├── sip_service.dart        # SIP protocol over WebSocket
│   │   ├── peer_service.dart       # WebRTC peer connection
│   │   └── backend_service.dart    # HTTP to Node backend
│   ├── screens/
│   │   ├── login_screen.dart       # Username + password entry
│   │   ├── dialer_screen.dart      # Phone number + call button
│   │   ├── incoming_screen.dart    # Accept/Reject incoming
│   │   └── incall_screen.dart      # In-call status + hangup
│   └── utils/
│       └── logger.dart             # Logging utilities
├── pubspec.yaml                    # Dependencies
└── IMPLEMENTATION_GUIDE.md         # This file
```

---

## 📖 Key Dependencies

```yaml
dependencies:
  flutter_webrtc: ^1.0.0           # WebRTC peer connections
  web_socket_channel: ^2.4.0       # SIP over WebSocket
  crypto: ^3.0.3                   # MD5 digest auth
  http: ^1.2.0                     # Backend API calls
```

---

## ✨ What's Next

### Future Enhancements
1. **Call history** — Save/display past calls
2. **Contacts integration** — Pick from phone contacts
3. **Mute/Hold** — Media control during call
4. **DTMF keypad** — Tone generation for menus
5. **Call transfer** — Blind/attended transfers
6. **Recording** — Capture calls for compliance
7. **Voicemail** — Auto-answer with message
8. **Presence** — Show availability status

---

## 📞 Support

- **Vobiz Docs:** https://docs.vobiz.ai
- **Flutter WebRTC:** https://tawk.to/flutter_webrtc
- **SIP RFC 3261:** https://tools.ietf.org/html/rfc3261

---

Generated with ❤️ for Vobiz mobile calling
