// lib/client/vobiz_client.dart
//
// Central controller - the single object the UI interacts with.
// Wires SIPService <-> PeerService and owns all shared state.

import 'dart:async';

import '../services/backend_service.dart';
import '../services/peer_service.dart';
import '../services/sip_service.dart';
import '../utils/logger.dart';

// ---------------------------------------------------------------------------
// State enums
// ---------------------------------------------------------------------------

enum ClientConnectionState { disconnected, connecting, connected }

enum RegistrationState { unregistered, registering, registered, failed }

enum CallState { idle, calling, incoming, ringing, inCall, ended }

// ---------------------------------------------------------------------------
// Immutable state snapshot
// ---------------------------------------------------------------------------

class VobizState {
  final ClientConnectionState connection;
  final RegistrationState registration;
  final CallState call;
  final String? callerId;
  final String? errorMessage;

  const VobizState({
    this.connection = ClientConnectionState.disconnected,
    this.registration = RegistrationState.unregistered,
    this.call = CallState.idle,
    this.callerId,
    this.errorMessage,
  });

  VobizState copyWith({
    ClientConnectionState? connection,
    RegistrationState? registration,
    CallState? call,
    String? callerId,
    String? errorMessage,
    bool clearError = false,
    bool clearCaller = false,
  }) {
    return VobizState(
      connection: connection ?? this.connection,
      registration: registration ?? this.registration,
      call: call ?? this.call,
      callerId: clearCaller ? null : (callerId ?? this.callerId),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

// ---------------------------------------------------------------------------
// VobizClient
// ---------------------------------------------------------------------------

class VobizClient {
  static const Duration _callSetupTimeout = Duration(seconds: 45);
  static const String _appDialNumber = String.fromEnvironment(
    'VOBIZ_APP_NUMBER',
    defaultValue: '',
  );
  // Your Vobiz phone number (CALLER_ID) - to prevent self-calls
  static const String _vobizPhoneNumber = String.fromEnvironment(
    'VOBIZ_CALLER_ID',
    defaultValue: '',
  );

  late final SIPService _sip;
  late final PeerService _peer;

  final _stateController = StreamController<VobizState>.broadcast();
  VobizState _state = const VobizState();
  Timer? _callSetupTimer;

  VobizState get state => _state;
  Stream<VobizState> get stream => _stateController.stream;
  ClientConnectionState get connectionState => _state.connection;
  RegistrationState get registrationState => _state.registration;
  CallState get callState => _state.call;

  VobizClient({required String wsUrl, required String sipServer}) {
    _sip = SIPService(wsUrl: wsUrl, sipServer: sipServer);
    _peer = PeerService();
    _wireSipCallbacks();
    _wirePeerCallbacks();
  }

  Future<void> connect(String username, String password) async {
    if (_state.connection != ClientConnectionState.disconnected) {
      Log.warn('Client', 'connect() ignored - already ${_state.connection}');
      return;
    }

    _emit(
      _state.copyWith(
        connection: ClientConnectionState.connecting,
        clearError: true,
      ),
    );

    try {
      await _sip.connect();
      _emit(_state.copyWith(connection: ClientConnectionState.connected));
      _emit(_state.copyWith(registration: RegistrationState.registering));
      _sip.register(username, password);
    } catch (e) {
      Log.error('Client', 'Connection error: $e');
      _emit(
        _state.copyWith(
          connection: ClientConnectionState.disconnected,
          errorMessage: 'Connection failed: $e',
        ),
      );
    }
  }

  Future<void> disconnect() async {
    _clearCallSetupTimer();
    await _peer.disposeAll();
    _sip.disconnect();
    _emit(const VobizState());
  }

  Future<void> call(String destination) async {
    if (_state.registration != RegistrationState.registered) {
      Log.warn('Client', 'call() ignored - not registered');
      return;
    }
    if (_state.call != CallState.idle) {
      Log.warn('Client', 'call() ignored - already in state: ${_state.call}');
      return;
    }
    final formattedDestination = _formatDestination(destination);
    if (formattedDestination.isEmpty) {
      _emit(_state.copyWith(errorMessage: 'Enter a phone number first'));
      return;
    }

    // Prevent calling your own Vobiz number (self-call)
    if (_isSameNumber(formattedDestination, _vobizPhoneNumber)) {
      Log.warn('Client', 'Cannot call own Vobiz number: $formattedDestination');
      _emit(_state.copyWith(
        errorMessage: 'Cannot call your own Vobiz number. Please dial a different number.',
      ));
      return;
    }

    _emit(_state.copyWith(call: CallState.calling, clearError: true));

    try {
      await _peer.createPeerConnection();
      await _peer.attachLocalAudioStream();
      final sdp = await _peer.createOffer();
      Log.info('Client', 'Offer SDP created, size: ${sdp.length} bytes');

      Log.info(
        'Client',
        'Calling backend to store destination: $formattedDestination',
      );
      await BackendService.makeCall(formattedDestination);

      final sipTarget = _resolveSipTarget(formattedDestination);
      Log.info('Client', 'Sending SIP INVITE to $sipTarget');
      _sip.call(sipTarget, sdp);
      _startCallSetupTimer();
    } catch (e) {
      Log.error('Client', 'Call setup failed: $e');
      _clearCallSetupTimer();
      await _peer.dispose();
      _emit(
        _state.copyWith(
          call: CallState.idle,
          errorMessage: _friendlyError(e),
        ),
      );
    }
  }

  Future<void> answer() async {
    if (_state.call != CallState.incoming) {
      Log.warn('Client', 'answer() ignored - not in incoming state');
      return;
    }

    try {
      print('📞 [ANSWER] Creating answer from stored offer...');
      final answerSdp = await _peer.createAnswerFromStoredOffer();
      print('📞 [ANSWER] Answer SDP created, length: ${answerSdp.length}');
      print('📞 [ANSWER] Sending SIP answer...');
      _sip.answer(answerSdp);
      print('📞 [ANSWER] SIP answer sent, call should be connected!');
      _emit(_state.copyWith(call: CallState.inCall, clearCaller: true));
    } catch (e, stack) {
      Log.error('Client', 'Answer failed: $e');
      print('❌ [ANSWER] Error: $e');
      print('❌ [ANSWER] Stack: $stack');
      _sip.reject();
      await _peer.dispose();
      _emit(
        _state.copyWith(
          call: CallState.idle,
          errorMessage: 'Failed to answer call',
          clearCaller: true,
        ),
      );
    }
  }

  Future<void> reject() async {
    if (_state.call != CallState.incoming) {
      Log.warn('Client', 'reject() ignored - not in incoming state');
      return;
    }

    _sip.reject();
    await _peer.dispose();
    _emit(_state.copyWith(call: CallState.idle, clearCaller: true));
  }

  Future<void> hangup() async {
    if (_state.call == CallState.idle) {
      Log.warn('Client', 'hangup() ignored - already idle');
      return;
    }

    Log.info('Client', 'Hanging up');
    _clearCallSetupTimer();
    _sip.hangup();
    await _peer.dispose();
    _emit(_state.copyWith(call: CallState.idle, clearCaller: true));
  }

  Future<void> dispose() async {
    _clearCallSetupTimer();
    await _peer.disposeAll();
    _sip.disconnect();
    await _stateController.close();
  }

  void _wireSipCallbacks() {
    _sip.onRegistered = () {
      _emit(
        _state.copyWith(
          registration: RegistrationState.registered,
          clearError: true,
        ),
      );
    };

    _sip.onRegistrationFailed = (reason) {
      Log.error('Client', 'Registration failed: $reason');
      _emit(
        _state.copyWith(
          registration: RegistrationState.failed,
          errorMessage: reason,
        ),
      );
    };

    _sip.onIncomingCall = (callerId, offerSdp) async {
      print('📞 [INBOUND] Incoming call from $callerId');
      print('📞 [INBOUND] Offer SDP length: ${offerSdp.length}');
      print('📞 [INBOUND] Offer SDP preview: ${offerSdp.substring(0, offerSdp.length > 200 ? 200 : offerSdp.length)}...');
      _emit(_state.copyWith(call: CallState.incoming, callerId: callerId));
      try {
        print('📞 [INBOUND] Creating peer connection...');
        await _peer.createPeerConnection();
        print('📞 [INBOUND] Attaching local audio stream...');
        await _peer.attachLocalAudioStream();
        print('📞 [INBOUND] Storing remote offer...');
        await _peer.storeRemoteOffer(offerSdp);
        print('📞 [INBOUND] Ready for user to answer!');
      } catch (e, stack) {
        Log.error('Client', 'Failed to prepare incoming call: $e');
        print('❌ [INBOUND] Error: $e');
        print('❌ [INBOUND] Stack: $stack');
        _sip.reject();
        _emit(
          _state.copyWith(
            call: CallState.idle,
            errorMessage: 'Failed to prepare call: ${_friendlyError(e)}',
            clearCaller: true,
          ),
        );
      }
    };

    _sip.onRemoteRinging = () {
      _clearCallSetupTimer();
      _emit(_state.copyWith(call: CallState.ringing, clearError: true));
    };

    _sip.onCallProgress = (progressSdp) async {
      _clearCallSetupTimer();
      if (progressSdp != null &&
          progressSdp.isNotEmpty &&
          !_peer.hasRemoteDescription) {
        try {
          await _peer.handleRemoteAnswer(progressSdp);
        } catch (e) {
          Log.warn('Client', 'Failed to apply early media SDP: $e');
        }
      }
      _emit(_state.copyWith(call: CallState.ringing, clearError: true));
    };

    _sip.onCallAnswered = (answerSdp) async {
      try {
        _clearCallSetupTimer();
        if (answerSdp.trim().isEmpty) {
          throw StateError('Received 200 OK without SDP answer');
        }
        if (!_peer.hasRemoteDescription) {
          await _peer.handleRemoteAnswer(answerSdp);
        }
        _emit(_state.copyWith(call: CallState.inCall));
      } catch (e) {
        Log.error('Client', 'Failed to apply remote answer: $e');
        _emit(
          _state.copyWith(
            call: CallState.idle,
            errorMessage: 'Failed to connect call',
          ),
        );
      }
    };

    _sip.onCallEnded = () async {
      _clearCallSetupTimer();
      await _peer.dispose();
      _emit(_state.copyWith(call: CallState.idle, clearCaller: true));
    };

    _sip.onCallFailed = (reason) async {
      _clearCallSetupTimer();
      await _peer.dispose();
      _emit(
        _state.copyWith(
          call: CallState.idle,
          errorMessage: reason,
          clearCaller: true,
        ),
      );
    };

    _sip.onSocketError = (reason) {
      _clearCallSetupTimer();
      _emit(
        _state.copyWith(
          connection: ClientConnectionState.disconnected,
          registration: RegistrationState.failed,
          call: CallState.idle,
          errorMessage: reason,
          clearCaller: true,
        ),
      );
    };
  }

  void _wirePeerCallbacks() {
    _peer.onRemoteStream = (stream) {
      // Remote audio plays automatically once the track is added.
    };

    _peer.onConnected = () {
      if (_state.call != CallState.inCall) {
        _emit(_state.copyWith(call: CallState.inCall));
      }
    };

    _peer.onDisconnected = () async {
      _clearCallSetupTimer();
      // Ensure SIP dialog state is cleared when WebRTC transport fails,
      // otherwise subsequent INVITEs can be rejected as "busy".
      _sip.hangup();
      await _peer.dispose();
      _emit(
        _state.copyWith(
          call: CallState.idle,
          errorMessage: 'Call disconnected unexpectedly',
          clearCaller: true,
        ),
      );
    };
  }

  void _emit(VobizState newState) {
    _state = newState;
    if (!_stateController.isClosed) {
      _stateController.add(_state);
    }
  }

  void _startCallSetupTimer() {
    _clearCallSetupTimer();
    _callSetupTimer = Timer(_callSetupTimeout, () async {
      if (_state.call != CallState.calling &&
          _state.call != CallState.ringing) {
        return;
      }

      Log.warn('Client', 'Call setup timed out');
      _sip.hangup();
      await _peer.dispose();
      _emit(
        _state.copyWith(
          call: CallState.idle,
          errorMessage:
              'Call timed out while waiting for the remote side to answer.',
          clearCaller: true,
        ),
      );
    });
  }

  void _clearCallSetupTimer() {
    _callSetupTimer?.cancel();
    _callSetupTimer = null;
  }

  String _friendlyError(Object e) {
    final msg = e.toString().toLowerCase();
    if (msg.contains('permission') || msg.contains('notallowed')) {
      return 'Microphone permission denied';
    }
    if (msg.contains('notfound') || msg.contains('devicenotfound')) {
      return 'No microphone found';
    }
    if (msg.contains('cleartext http traffic')) {
      return 'Local backend HTTP is blocked. Use HTTPS or allow cleartext traffic.';
    }
    if (msg.contains('socket') || msg.contains('websocket')) {
      return 'Network error - check your connection';
    }
    return 'Something went wrong';
  }

  String _formatDestination(String input) {
    final digits = input.trim().replaceAll(RegExp(r'[^0-9+]'), '');
    if (digits.isEmpty) return '';
    if (digits.startsWith('+')) return digits;

    if (digits.length == 10) return '+91$digits';
    if (digits.length == 11 && digits.startsWith('0')) {
      return '+91${digits.substring(1)}';
    }
    return '+$digits';
  }

  String _resolveSipTarget(String formattedDestination) {
    final appDial = _appDialNumber.trim();
    if (appDial.isEmpty) {
      return formattedDestination;
    }
    return _formatDestination(appDial);
  }

  /// Compare two phone numbers, ignoring formatting differences
  bool _isSameNumber(String a, String b) {
    final left = a.replaceAll(RegExp(r'[^0-9]'), '');
    final right = b.replaceAll(RegExp(r'[^0-9]'), '');
    return left.isNotEmpty && left == right;
  }
}
