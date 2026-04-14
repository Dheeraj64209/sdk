Detailed Project Understanding
1. What this repository is
This repo is a Vobiz voice-calling setup that combines:

A backend Answer-URL server (Vobiz-RTC-demo) that returns Vobiz XML (<Dial>...)
A Flutter SIP/WebRTC calling app (_zipinspect/vobiz_flutter) for real mobile calling
A reusable Flutter SDK scaffold (packages/vobiz_webrtc) with event streams and modular call/signaling abstractions
A demo SDK consumer app (apps/vobiz_demo) that demonstrates package integration
You currently have two main variants:

vobiz_inbound: full inbound + outbound routing behavior
vobiz_final: outbound-focused setup (simpler Answer URL behavior)
2. Folder-level architecture
vobiz_inbound
Vobiz-RTC-demo/
Node backend with endpoints:

POST /call (store outbound destination)
GET|POST /answer (routing decision + XML response)
GET|POST /hangup (empty XML response)
POST /register-token (stores push token in memory map)
_zipinspect/vobiz_flutter/
Primary Flutter implementation used for SIP registration and call handling.

packages/vobiz_webrtc/
Modular SDK-style package (VobizClient, SdkConfig, event streams, call/session state).

apps/vobiz_demo/
Demo app that uses packages/vobiz_webrtc.

vobiz_final
Same broad structure, but backend Answer URL logic is primarily outbound-oriented and does not include the same inbound routing depth as vobiz_inbound.

3. Inbound vs Outbound calling (core concept)
Outbound calling
Outbound means: user initiates call from app to destination number (PSTN/SIP).

High-level:

App registers SIP endpoint
User enters destination
App posts destination to backend (/call)
App sends SIP INVITE + SDP offer
Vobiz asks backend /answer
Backend returns <Dial><Number>destination</Number></Dial>
Vobiz bridges call
Inbound calling
Inbound means: external PSTN caller dials your Vobiz number, app receives incoming call.

High-level:

App must already be online and SIP-registered
PSTN caller dials your Vobiz number
Vobiz asks backend /answer
Backend returns <Dial><User>sip:endpoint@registrar...</User></Dial>
SIP INVITE reaches app
App shows incoming call UI
User accepts/rejects; if accepted, answer SDP completes media
4. Detailed backend behavior (vobiz_inbound/Vobiz-RTC-demo/server.js)
The backend is the call-routing brain.

Important env variables
CALLER_ID: outbound caller ID
SIP_ENDPOINT: SIP URI for inbound call routing
DEFAULT_DESTINATION: fallback outbound destination
DEFAULT_COUNTRY_CODE: normalization helper
Key internal logic
Normalizes numbers to E.164 style (+...)
Prevents self-calls (destination == callerId)
Parses query/body params for both GET and POST webhook styles
Distinguishes call type in /answer:
SDK/outbound leg: From starts with sip: or RouteType=sip
Inbound PSTN leg: otherwise
Endpoint behavior
POST /call: stores lastDialedNumber for next outbound bridge
GET|POST /answer:
Outbound path -> returns <Dial><Number>...</Number></Dial>
Inbound path -> returns <Dial><User>${SIP_ENDPOINT}</User></Dial>
GET|POST /hangup: returns empty <Response></Response>
POST /register-token: stores token in registeredPushTokens map (in-memory)
5. Primary Flutter app internals (_zipinspect/vobiz_flutter)
This is the app that actually performs SIP + media call flows.

Main runtime pieces
lib/main.dart: route resolution by call/registration state
lib/client/vobiz_client.dart: central state machine and orchestration
lib/services/sip_service.dart: SIP over WebSocket (REGISTER/INVITE/ACK/BYE, digest auth)
lib/services/peer_service.dart: WebRTC peer connection, offer/answer, ICE handling
lib/services/backend_service.dart: backend API (POST /call)
lib/screens/*: login, dialer, incoming, in-call UI
What VobizClient (app-side) does
Connect and register SIP endpoint
Handle outbound call setup:
create peer
attach mic
create offer
call backend /call
send SIP INVITE
Handle inbound call setup:
receive INVITE callback
prepare peer + store offer SDP
expose incoming screen
on accept -> create/send answer
Handle disconnect/hangup/error transitions
Apply timeout for stalled call setup
SIP service depth
Maintains WebSocket SIP transport
Sends REGISTER and handles 401/407 digest challenges
Handles incoming INVITE/BYE/CANCEL/OPTIONS
Handles INVITE responses (100/180/183/200/4xx/6xx)
Resends 180/200 on retransmits where needed
Maintains dialog identifiers (Call-ID, tags, CSeq)
WebRTC service depth
Creates peer connection with STUN (+ optional TURN via dart-define)
Captures local audio track
Creates and applies SDP offer/answer
Queues ICE candidates until remote description is ready
Sanitizes SDP and retries remote description set for robustness
6. Reusable Flutter SDK package (packages/vobiz_webrtc)
This is a modular scaffolded SDK layer, separate from _zipinspect app implementation.

Exposed API style
VobizClient(config: SdkConfig(...))
event streams:
connectionEvents
callEvents
mediaEvents
errorEvents
methods:
connect(...)
makeCall(...)
acceptCall(...)
rejectCall(...)
hangup(...)
mute/unmute
candidate handling
Internal modules
SocketService: signaling transport + reconnect policy
CallManager: call lifecycle state transitions
PeerService: media and peer handling
models/events/state enums for clean SDK contracts
Why this exists
Reusability and separation for future productization
Lets teams integrate calling via a package interface instead of direct app internals
apps/vobiz_demo proves this package usage pattern
7. What you need from Vobiz (external requirements)
Before running real calls, you need these in Vobiz Console:

Vobiz number for caller ID (CALLER_ID)
Endpoint credentials (username/password) for SIP registration
Endpoint SIP URI (for inbound routing in vobiz_inbound)
Voice Application configured with:
Answer URL: https://<public-url>/answer
Hangup URL: https://<public-url>/hangup
Number/application mapping configured in dashboard
Without these, registration/call bridging/inbound delivery will fail.

8. Push notification status (important reality)
In vobiz_inbound:

POST /register-token exists
tokens are stored in-memory map (registeredPushTokens)
No full APNs/FCM dispatch pipeline is implemented in this repo
no durable token store, no provider send flow, no production push worker
So current effective inbound model is:

app must be active/online and SIP-registered to receive incoming calls reliably
Push plumbing is partially scaffolded at backend API level, but not complete end-to-end push-notification infrastructure yet.

9. End-to-end workflow summary
Outbound summary
User login (SIP register)
User dial
App posts destination to /call
App sends INVITE
Vobiz calls /answer
Backend returns <Dial><Number>
Call connected
Inbound summary (vobiz_inbound)
App already registered
PSTN caller dials Vobiz number
Vobiz calls /answer
Backend returns <Dial><User>${SIP_ENDPOINT}</User>
App receives incoming INVITE
Accept/reject
If accept -> active call with RTP media
