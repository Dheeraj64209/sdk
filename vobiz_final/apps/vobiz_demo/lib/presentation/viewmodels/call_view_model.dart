import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:vobiz_webrtc/vobiz_webrtc.dart';

/// View model for the dialer screen.
///
/// It owns the entered number, starts calls through the SDK, and keeps a small
/// UI-friendly snapshot of the active call state.
class CallViewModel extends ChangeNotifier {
  CallViewModel(this.client) {
    _callSub = client.callEvents.listen((CallEvent event) {
      final dynamic session = event.session;
      latestCallEvent = event;
      activeCallId = event.callId;
      currentRemoteIdentity = session?.remoteIdentity as String?;
      isMuted = session?.muted as bool? ?? isMuted;
      isCalling = event.state == CallStateStatus.connecting ||
          event.state == CallStateStatus.ringing ||
          event.state == CallStateStatus.active ||
          event.state == CallStateStatus.held;
      isIncomingRinging = session?.isIncoming == true &&
          (event.state == CallStateStatus.incoming ||
              event.state == CallStateStatus.ringing);
      if (event.state == CallStateStatus.ended ||
          event.state == CallStateStatus.failed) {
        activeCallId = null;
        isCalling = false;
        isIncomingRinging = false;
        isMuted = false;
        currentRemoteIdentity = null;
      }
      notifyListeners();
    });

    _errorSub = client.errorEvents.listen((ErrorEvent event) {
      errorMessage = event.message;
      notifyListeners();
    });
  }

  final VobizClient client;

  StreamSubscription<CallEvent>? _callSub;
  StreamSubscription<ErrorEvent>? _errorSub;

  String destination = '';
  String? activeCallId;
  CallEvent? latestCallEvent;
  String? currentRemoteIdentity;
  bool isBusy = false;
  bool isCalling = false;
  bool isIncomingRinging = false;
  bool isMuted = false;
  String? errorMessage;

  String get enteredNumber => destination;
  String get remoteIdentity => currentRemoteIdentity?.isNotEmpty == true
      ? currentRemoteIdentity!
      : destination.trim();
  bool get canMute => activeCallId != null && isCalling;
  bool get canHangup => activeCallId != null;

  void setDestination(String value) {
    destination = value;
    notifyListeners();
  }

  void appendDigit(String value) {
    destination = '$destination$value';
    notifyListeners();
  }

  void backspace() {
    if (destination.isEmpty) {
      return;
    }
    destination = destination.substring(0, destination.length - 1);
    notifyListeners();
  }

  Future<void> makeCall() async {
    if (destination.trim().isEmpty) {
      errorMessage = 'Enter a number before placing a call.';
      notifyListeners();
      return;
    }

    isBusy = true;
    errorMessage = null;
    notifyListeners();

    try {
      activeCallId = await client.makeCall(destination.trim());
    } catch (error) {
      errorMessage = error.toString();
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }

  Future<void> hangup() async {
    final String? callId = activeCallId;
    if (callId == null) {
      return;
    }
    await client.hangup(callId);
  }

  Future<void> acceptIncomingCall() async {
    errorMessage = null;
    notifyListeners();
    try {
      await client.acceptCall(activeCallId);
      isIncomingRinging = false;
    } catch (error) {
      errorMessage = error.toString();
    } finally {
      notifyListeners();
    }
  }

  Future<void> rejectIncomingCall() async {
    errorMessage = null;
    notifyListeners();
    try {
      await client.rejectCall(activeCallId);
      isIncomingRinging = false;
    } catch (error) {
      errorMessage = error.toString();
    } finally {
      notifyListeners();
    }
  }

  Future<void> toggleMute() async {
    final String? callId = activeCallId;
    if (callId == null) {
      return;
    }

    try {
      if (isMuted) {
        await client.unmute(callId);
        isMuted = false;
      } else {
        await client.mute(callId);
        isMuted = true;
      }
    } catch (error) {
      errorMessage = error.toString();
    } finally {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _callSub?.cancel();
    _errorSub?.cancel();
    super.dispose();
  }
}
