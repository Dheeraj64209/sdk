import 'dart:async';

import '../events/call_event.dart';
import '../models/call/dtmf_tone.dart';
import '../models/call/incoming_call.dart';
import '../state/call_state.dart';
import '../utils/stream_extensions.dart';
import 'call_session.dart';

/// Stream-based call state manager for the SDK.
///
/// It keeps track of the known calls and emits a [CallEvent] every time a call
/// changes state. The implementation uses a broadcast stream so multiple parts
/// of the app can listen at the same time.
class CallManager {
  final StreamController<CallEvent> _callEvents =
      StreamController<CallEvent>.broadcast();

  final Map<String, CallSession> _calls = <String, CallSession>{};

  /// Broadcast stream for all call state changes.
  Stream<CallEvent> get callEvents => _callEvents.stream;

  /// All currently tracked calls.
  Iterable<CallSession> get calls => _calls.values;

  /// Returns the latest call that is still active in local state.
  CallSession? get currentCall {
    for (final CallSession session in _calls.values.toList().reversed) {
      if (session.state != CallStateStatus.ended &&
          session.state != CallStateStatus.failed) {
        return session;
      }
    }
    return null;
  }

  /// Creates an outgoing call.
  ///
  /// Outgoing calls start from `idle`, then transition to `ringing` or
  /// `active` depending on signaling progress.
  CallSession createOutgoing({
    required String callId,
    required String destination,
    String? answerUrl,
    Map<String, dynamic> metadata = const <String, dynamic>{},
  }) {
    final CallSession session = CallSession(
      callId: callId,
      remoteIdentity: destination,
      isIncoming: false,
      answerUrl: answerUrl,
      state: CallStateStatus.idle,
      metadata: metadata,
    );

    _calls[callId] = session;
    _emit(session, 'Outgoing call created');
    return session;
  }

  /// Creates an incoming call.
  ///
  /// Incoming calls enter the `ringing` state immediately so the UI can show an
  /// incoming-call screen or local ringtone.
  CallSession createIncoming(IncomingCall incoming, {String? answerUrl}) {
    final CallSession session = CallSession(
      callId: incoming.callId,
      remoteIdentity: incoming.callerNumber,
      isIncoming: true,
      answerUrl: answerUrl,
      state: CallStateStatus.ringing,
      metadata: incoming.metadata,
    );

    _calls[incoming.callId] = session;
    _emit(session, 'Incoming call received');
    return session;
  }

  /// Finds a call by ID.
  CallSession? getById(String callId) => _calls[callId];

  /// Moves a call into the `idle` state.
  void setIdle(String callId, {String? message}) {
    updateState(callId, CallStateStatus.idle, message: message ?? 'Call idle');
  }

  /// Moves a call into the `ringing` state.
  void setRinging(String callId, {String? message}) {
    updateState(
      callId,
      CallStateStatus.ringing,
      message: message ?? 'Call ringing',
    );
  }

  /// Moves a call into the `active` state.
  void setActive(String callId, {String? message}) {
    updateState(
      callId,
      CallStateStatus.active,
      message: message ?? 'Call active',
    );
  }

  /// Marks the local media for a call as muted.
  ///
  /// This does not directly manipulate WebRTC tracks. It updates local state so
  /// the UI and higher-level services can react consistently.
  void mute(String callId, {String? message}) {
    final CallSession session = _requireCall(callId);
    session.muted = true;
    _emit(session, message ?? 'Call muted');
  }

  /// Marks the local media for a call as unmuted.
  void unmute(String callId, {String? message}) {
    final CallSession session = _requireCall(callId);
    session.muted = false;
    _emit(session, message ?? 'Call unmuted');
  }

  /// Puts a call on hold by moving it into the `held` state.
  void hold(String callId, {String? message}) {
    final CallSession session = _requireCall(callId);
    session.state = CallStateStatus.held;
    _emit(session, message ?? 'Call on hold');
  }

  /// Resumes a held call by moving it back to the `active` state.
  void resume(String callId, {String? message}) {
    final CallSession session = _requireCall(callId);
    session.state = CallStateStatus.active;
    _emit(session, message ?? 'Call resumed');
  }

  /// Records a DTMF tone against the call state and emits an update event.
  ///
  /// The tone history is stored in session metadata so higher layers can inspect
  /// the digits that were sent without needing a separate state object.
  void sendDtmf(
    String callId,
    DtmfTone tone, {
    String? message,
  }) {
    final CallSession session = _requireCall(callId);
    final List<String> tones = (session.metadata['dtmfTones'] as List<dynamic>?)
            ?.map((dynamic value) => value.toString())
            .toList() ??
        <String>[];
    tones.add(tone.value);
    session.metadata['dtmfTones'] = tones;
    _emit(session, message ?? 'DTMF tone sent: ${tone.value}');
  }

  /// Marks a call as ended and removes it from the live map.
  void endCall(String callId, {String? message}) {
    remove(callId, message: message ?? 'Call ended');
  }

  /// Generic state transition helper used by the rest of the SDK.
  void updateState(String callId, CallStateStatus state, {String? message}) {
    final CallSession? session = _calls[callId];
    if (session == null) {
      return;
    }

    session.state = state;
    _emit(session, message);
  }

  /// Removes a call from memory after moving it to `ended`.
  void remove(String callId, {String? message}) {
    final CallSession? session = _calls.remove(callId);
    if (session == null) {
      return;
    }

    session.state = CallStateStatus.ended;
    _emit(session, message ?? 'Call removed');
  }

  /// Clears all tracked calls.
  void clear() {
    _calls.clear();
  }

  /// Closes the event stream when the manager is no longer reused.
  Future<void> dispose() async {
    await _callEvents.close();
  }

  // Looks up a call and throws when it does not exist.
  CallSession _requireCall(String callId) {
    final CallSession? session = _calls[callId];
    if (session == null) {
      throw StateError('Call $callId not found');
    }
    return session;
  }

  // Emits one normalized event for every call state change.
  void _emit(CallSession session, String? message) {
    _callEvents.addIfOpen(
      CallEvent(
        callId: session.callId,
        state: session.state,
        session: session,
        message: message,
      ),
    );
  }
}
