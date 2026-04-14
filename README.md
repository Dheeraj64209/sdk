Project Overview
This repository is a Vobiz voice-calling setup with two working variants:

Folder	Purpose
vobiz_inbound	Full setup for both outbound + inbound calling
vobiz_final	Simpler setup, mainly outbound-focused
Each variant contains:

Vobiz-RTC-demo/ → Node backend (Answer URL XML server)
_zipinspect/vobiz_flutter/ → primary Flutter SIP/WebRTC app
packages/vobiz_webrtc/ → reusable Flutter SDK scaffold
apps/vobiz_demo/ → demo app using the SDK package
Inbound vs Outbound (Simple Meaning)
Outbound calling
User starts a call from the app to a destination number.

App registers SIP endpoint
User dials a number
App calls backend POST /call
App sends SIP INVITE
Vobiz hits /answer
Backend returns <Dial><Number>...</Number></Dial>
Call is bridged to PSTN
Inbound calling
Someone dials your Vobiz number, and your app receives the call.

App must already be SIP-registered
PSTN caller dials your Vobiz number
Vobiz hits /answer
Backend returns <Dial><User>sip:...@registrar.vobiz.ai</User></Dial>
App gets incoming SIP INVITE
User accepts/rejects
If accepted, media starts
What the Flutter app does (_zipinspect/vobiz_flutter)
Main responsibilities:

SIP login/registration
Outbound call setup
Incoming call handling UI
WebRTC media setup (mic, SDP, ICE)
Call state transitions and error handling
Key runtime pieces:

client/vobiz_client.dart → app call state machine
services/sip_service.dart → SIP signaling over WebSocket
services/peer_service.dart → WebRTC offer/answer + ICE
services/backend_service.dart → backend /call API
screens/* → login/dialer/incoming/incall screens
What the SDK package is (packages/vobiz_webrtc)
This is a modular SDK-style scaffold (reusable layer), separate from the direct app implementation.

It provides:

VobizClient API
SdkConfig
event streams:
connectionEvents
callEvents
mediaEvents
errorEvents
call actions like connect, make/accept/reject/hangup, mute/unmute
It is consumed by apps/vobiz_demo.

Backend behavior (Vobiz-RTC-demo)
Core endpoints:

POST /call → store outbound destination
GET|POST /answer → return routing XML
GET|POST /hangup → return empty XML
POST /register-token → stores push token in memory
In vobiz_inbound, /answer chooses flow:

Outbound SDK leg -> returns <Dial><Number>
Inbound PSTN leg -> returns <Dial><User> using SIP_ENDPOINT
What you need from Vobiz
You must have:

A Vobiz number (CALLER_ID)
SIP endpoint credentials (username/password)
SIP endpoint URI (sip:<user>@registrar.vobiz.ai)
Voice Application with:
Answer URL: https://<public-url>/answer
Hangup URL: https://<public-url>/hangup
Number linked to that application

Required .env (for vobiz_inbound)
CALLER_ID=+<your-vobiz-number>
SIP_ENDPOINT=sip:<your-endpoint-username>@registrar.vobiz.ai
DEFAULT_DESTINATION=+<optional-test-number>
DEFAULT_COUNTRY_CODE=91


Push notifications (current status)
Current implementation status:

Backend has POST /register-token
Tokens are stored in-memory (registeredPushTokens)
Full APNs/FCM sending pipeline is not implemented in this repo
So in practice, inbound calls are reliable when app is online and registered to SIP.
Background wake-up push flow is scaffolded but not fully production-ready.

