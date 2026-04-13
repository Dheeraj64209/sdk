# 🚀 Quick Start Checklist — Vobiz Flutter App

## Pre-Flight Checklist

- [ ] **Get Vobiz Credentials**
  - [ ] Go to [Vobiz Console](https://console.vobiz.ai)
  - [ ] Navigate to Voice > Endpoints
  - [ ] Copy endpoint **Username** (e.g., `user123456789`)
  - [ ] Copy endpoint **Password**

- [ ] **Setup Local Network**
  - [ ] Ensure phone and laptop are on same WiFi
  - [ ] Note your laptop IP address (e.g., `<your-lan-ip>`)
  - [ ] Test reachability: laptop must be reachable from phone

- [ ] **Get Flutter & Device**
  - [ ] Flutter 3.10+ installed
  - [ ] Physical Android or iOS device (not emulator)
  - [ ] Device connected via USB with ADB enabled (Android)

---

## Startup Steps (Do This Every Time)

### Terminal 1: Start Node Backend

```bash
cd ~/vobiz2/Vobiz-RTC-demo
npm install                # (first time only)
npm start
```

**Expected Output:**
```
-------------------------------------------------------
  Vobiz Backend running on port 3000
-------------------------------------------------------
  Frontend (Web UI):
     http://localhost:3000/client/index.html

  Flutter calls:
     http://<your-lan-ip>:3000/call

  Vobiz Answer URL:
     https://<your-ngrok-url>/
-------------------------------------------------------
```

**Status:** ✅ Backend running

### Terminal 2: Launch Flutter App

```bash
cd ~/vobiz2/_zipinspect/vobiz_flutter
flutter pub get              # (first time only)
flutter devices             # See available devices
flutter run -d <device-id>  # Launch on your device
```

**Expected Output:**
```
✓ Build complete!
Launching lib/main.dart on your-device in release mode...
```

**Status:** ✅ App running on device

---

## Test Sequence

### Test 1: Connection & Registration (2 minutes)

**Setup:** Frontend running, phone on same WiFi

**Steps:**
1. App opens → Shows **Login Screen**
2. Enter **Username** (from Vobiz Console)
3. Enter **Password** (from Vobiz Console)
4. Tap **Connect**
5. Watch for **"Registered"** (green indicator)

**Expected Result:**
- [ ] Username field accepts input
- [ ] Password field masks input
- [ ] Status shows "Connecting..."
- [ ] Status shows "Registered" (green dot)
- [ ] Backend log shows SIP REGISTER messages
- [ ] Time to register: 1-3 seconds

**If Fails:**
```
❌ "Registration failed (403)"
→ Check username/password in Vobiz Console

❌ "Connection failed"
→ Check backend is running
→ Check WiFi connection
→ Check firewall isn't blocking
```

### Test 2: Dialer Screen (1 minute)

**Setup:** Status shows "Registered"

**Steps:**
1. App shows **Dialer Screen** with "Registered" in green
2. Text field labeled "Phone number" is active
3. Tap text field
4. Type: `+1234567890` (or any test number)
5. Tap **Call** button (should be enabled)

**Expected Result:**
- [ ] Dialer Screen displays correctly
- [ ] Text field accepts input
- [ ] "Call" button becomes enabled when number entered
- [ ] Screen transitions to show call status
- [ ] Status shows **"Calling..."**

**If Fails:**
```
❌ "Call button disabled"
→ Check registration (should show "Registered")

❌ "Empty phone number" snackbar
→ Enter a phone number first

❌ "Call setup failed"
→ Check backend is running
→ Check microphone permission is granted
```

### Test 3: Outbound Call Flow (3-5 minutes)

**Setup:** Number entered, tapped "Call"

**What Should Happen:**
1. **Calling...** (status) — WebRTC peer connecting
2. **Ringing...** (status) — Phone ringing on destination
3. **In Call** (status) — Call established
4. Tap **End Call** — Back to Dialer
5. Backend logs show `/call` POST request + Answer URL query

**Expected Logs in Flutter:**
```
[Client] Offer SDP created
[Client] Calling backend to store destination
[Backend] Response status: 200
[Client] Sending SIP INVITE
[SIP] >> INVITE sip:...
[SIP] << 180 Ringing
[SIP] << 200 OK
[WebRTC] Peer connected
```

**If Fails:**
```
❌ "Stays on Calling... forever"
→ Check SIP server reachability
→ Check Vobiz Answer URL configured
→ Check destination phone is valid

❌ "Backend timeout after 10 seconds"
→ Check http://<your-lan-ip>:3000 is reachable
→ Check Node backend is running
→ Check WiFi connection

❌ "No audio during call"
→ Check microphone permission
→ Check STUN server reachability
→ Use physical device (not emulator)
```

### Test 4: Incoming Call (3-5 minutes)

**Setup:** App registered, ready to receive call

**How to Test:**
- Option A: Call the endpoint from another SIP client
- Option B: Call the PSTN number (if set up in Vobiz)
- Option C: Have a friend call if Vobiz number is active

**What Should Happen:**
1. **IncomingScreen** appears with caller ID
2. Tap **Accept** → transitions to **In Call**
3. Audio flows between caller and Flutter app
4. Tap **End Call** → back to Dialer
5. Tap **Reject** (instead of accept) → back to Dialer

**Expected Text:**
```
Incoming call
Caller Name (or Unknown)

[Accept] [Reject]
```

**If Fails:**
```
❌ "No incoming call screen"
→ Check SIP endpoint can receive calls
→ Check Vobiz dashboard shows incoming INVITE
→ Check backend Answer URL is configured

❌ "Call screen but no audio"
→ Check microphone permission
→ Check speaker is unmuted
→ Check STUN servers reachable
```

### Test 5: Error Handling (1 minute)

**Test disconnection:**
1. Stop Node backend (Ctrl+C in Terminal 1)
2. Try to make a call from app
3. Should see error message within 10 seconds
4. Restart backend

**Test wrong credentials:**
1. Disconnect
2. Try login with wrong password
3. Should see "Registration failed" message

**Test network down:**
1. Disconnect WiFi
2. Try to connect
3. Should see "Connection failed" message

**Expected Behavior:**
- [ ] Errors shown within 10 seconds
- [ ] Messages are user-friendly
- [ ] App doesn't hang or crash
- [ ] Can retry after fixing issue

---

## Production Setup (Optional)

**Only needed if deploying to PSTN:**

### 1. Expose Backend to Internet

```bash
# Get ngrok (https://ngrok.com/download)
ngrok http 3000

# Get output like:
# https://abc123.ngrok.io -> http://localhost:3000
```

### 2. Update Vobiz Dashboard

Go to [Vobiz Console](https://console.vobiz.ai):
1. **Voice > Applications**
2. Create/Edit application
3. Set **Answer URL** to: `https://abc123.ngrok.io/`
4. Link your phone number to this application

### 3. Test with PSTN

- Call your Vobiz number from any phone
- Should see incoming call on app
- Accept and talk

---

## Debugging Tips

### View Real-Time Logs

**Flutter Bottom Bar:**
```
flutter logs
```

**Node Backend Console:**
Already showing logs (look for `[timestamp]` entries)

**Look for these tags:**
- `[Client]` — App state changes
- `[SIP]` — SIP messages
- `[WebRTC]` — Peer connection
- `[Backend]` — HTTP requests

### Check Backend is Running

```bash
curl http://<your-lan-ip>:3000/
# Should return HTML or 404, not "Connection refused"
```

### Check WiFi Connection

```bash
# From phone:
ping <your-lan-ip>
# Should get responses, not "Host unreachable"
```

### Monitor WebRTC

In Flutter output, look for:
```
[WebRTC] Peer connection created
[WebRTC] Local audio stream attached
[WebRTC] Peer connected — media flowing
```

---

## Common Issues & Fixes

| Issue | Solution |
|-------|----------|
| "Registration failed (403)" | Check Vobiz credentials |
| "Backend timeout after 10s" | Check http://<your-lan-ip>:3000 reachable |
| "Call setup failed" | Check microphone permission granted |
| "No incoming call screen" | Check Answer URL in Vobiz Console |
| "No audio during call" | Check speaker ON, use physical device |
| "App crashes on launch" | Run `flutter pub get` first |
| "Device not detected" | Run `adb devices` (Android) |

---

## Success Checklist

After running all tests, you should have:

- [ ] ✅ App launches successfully
- [ ] ✅ Login works with Vobiz credentials
- [ ] ✅ Status shows "Registered" (green)
- [ ] ✅ Dialer screen displays correctly
- [ ] ✅ Outbound call shows "Calling..." → "Ringing..." → "In Call"
- [ ] ✅ Can hear/speak during call
- [ ] ✅ Hangup works, back to dialer
- [ ] ✅ Backend logs show `/call` requests
- [ ] ✅ Errors handled gracefully
- [ ] ✅ App doesn't crash

**If all above pass: 🎉 YOUR APP IS WORKING!**

---

## Support Resources

- **Vobiz Documentation:** https://docs.vobiz.ai
- **Flutter WebRTC Docs:** https://pub.dev/packages/flutter_webrtc
- **SIP Information:** https://en.wikipedia.org/wiki/Session_Initiation_Protocol
- **This Project:** See IMPLEMENTATION_GUIDE.md for detailed docs

---

## Quick Commands Reference

```bash
# Start backend
cd Vobiz-RTC-demo && npm start

# Run Flutter app
flutter run -d <device-id>

# View Flutter logs
flutter logs

# List connected devices
flutter devices

# Clean rebuild
flutter clean && flutter pub get && flutter run

# Check WiFi IP
ipconfig (Windows)
ifconfig (Mac/Linux)

# Test network connectivity
ping <your-lan-ip>
curl http://<your-lan-ip>:3000
```

---

**Ready to test? Start with "Startup Steps" above! 🚀**
