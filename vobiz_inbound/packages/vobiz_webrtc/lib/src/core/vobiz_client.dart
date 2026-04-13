import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../calls/call_manager.dart';
import '../calls/call_session.dart';
import '../events/call_event.dart';
import '../events/connection_event.dart';
import '../events/error_event.dart';
import '../events/media_event.dart';
import '../models/auth/credential_config.dart';
import '../models/auth/token_config.dart';
import '../models/call/incoming_call.dart';
import '../models/signaling/answer_message.dart';
import '../models/signaling/bye_message.dart';
import '../models/signaling/candidate_message.dart';
import '../models/signaling/invite_message.dart';
import '../repositories/call_repository.dart';
import '../repositories/session_repository.dart';
import '../signaling/socket_protocol.dart';
import '../signaling/socket_service.dart';
import '../state/call_state.dart';
import '../state/connection_state.dart';
import '../state/registration_state.dart';
import '../utils/logger.dart';
import '../utils/stream_extensions.dart';
import '../webrtc/peer_service.dart';
import 'sdk_config.dart';
import 'sdk_constants.dart';

/// Main client used by the SDK consumer to manage signaling and call state.
///
/// The design mirrors the responsibilities of `TelnyxClient`:
/// - open and close the signaling socket
/// - authenticate with login credentials or token credentials
/// - expose broadcast event streams for connection, call, media, and errors
/// - keep internal state in sync with socket and signaling messages
class VobizClient {
  VobizClient({
    SdkConfig config = const SdkConfig(),
    Logger? logger,
  })  : _logger = logger ?? Logger(),
        _config = config,
        _callRepository = CallRepository(),
        _sessionRepository = SessionRepository(),
        _callManager = CallManager(),
        _socketService = SocketService(
          socketUrl: config.socketUrl ?? SdkConstants.defaultSocketUrl,
          autoReconnect: config.autoReconnect,
          logger: logger,
        ),
        _peerService = PeerService(
          iceConfig: config.iceConfig,
          mediaConstraints: config.mediaConstraints,
          logger: logger,
        ) {
    _wireServices();
  }

  // Core services used by the client.
  final Logger _logger;
  final SdkConfig _config;
  final CallRepository _callRepository;
  final SessionRepository _sessionRepository;
  final CallManager _callManager;
  final SocketService _socketService;
  final PeerService _peerService;

  // Public event streams.
  final StreamController<ConnectionEvent> _connectionEvents =
      StreamController<ConnectionEvent>.broadcast();
  final StreamController<CallEvent> _callEvents =
      StreamController<CallEvent>.broadcast();
  final StreamController<MediaEvent> _mediaEvents =
      StreamController<MediaEvent>.broadcast();
  final StreamController<ErrorEvent> _errorEvents =
      StreamController<ErrorEvent>.broadcast();

  // Subscriptions are tracked so the client can clean them up if disposed later.
  final List<StreamSubscription<dynamic>> _subscriptions =
      <StreamSubscription<dynamic>>[];

  RegistrationState _registrationState = RegistrationState.unregistered;
  ConnectionStateStatus _connectionState = ConnectionStateStatus.disconnected;
  bool _isConnected = false;

  /// Broadcasts connection and registration changes.
  Stream<ConnectionEvent> get connectionEvents => _connectionEvents.stream;

  /// Broadcasts call lifecycle changes.
  Stream<CallEvent> get callEvents => _callEvents.stream;

  /// Broadcasts local and remote media updates.
  Stream<MediaEvent> get mediaEvents => _mediaEvents.stream;

  /// Broadcasts recoverable and fatal SDK errors.
  Stream<ErrorEvent> get errorEvents => _errorEvents.stream;

  /// Returns all known calls currently held by the client.
  Iterable<CallSession> get calls => _callManager.calls;

  /// Returns the current connection state snapshot.
  ConnectionStateStatus get connectionState => _connectionState;

  /// Returns the current registration state snapshot.
  RegistrationState get registrationState => _registrationState;

  /// Returns whether the signaling session is currently established.
  bool get isConnected => _isConnected;

  /// Returns the most recent call that is still actionable.
  ///
  /// This allows convenience methods like [acceptCall] and [rejectCall] to
  /// work without forcing the consumer to pass a call ID every time.
  CallSession? get currentCall {
    for (final CallSession call in _callManager.calls.toList().reversed) {
      if (call.state != CallStateStatus.ended &&
          call.state != CallStateStatus.failed) {
        return call;
      }
    }
    return null;
  }

  /// Connects the client using either [CredentialConfig] or [TokenConfig].
  ///
  /// This is the main login entry point requested by the API contract.
  Future<void> connect(Object credentials) async {
    if (credentials is CredentialConfig) {
      await connectWithCredentials(credentials);
      return;
    }

    if (credentials is TokenConfig) {
      await connectWithToken(credentials);
      return;
    }

    throw ArgumentError(
      'Unsupported credentials type: ${credentials.runtimeType}. '
      'Use CredentialConfig or TokenConfig.',
    );
  }

  /// Connects with username/password style credentials.
  Future<void> connectWithCredentials(CredentialConfig config) async {
    await _connectInternal(
      userId: config.username,
      successMessage: 'Credential login sent',
      loginCommand: SocketCommand.login,
      payload: <String, dynamic>{
        'username': config.username,
        'password': config.password,
        if (config.displayName != null) 'displayName': config.displayName,
        'answerUrl': config.answerUrl ?? _config.answerUrl,
      },
    );
  }

  /// Connects with a server-issued token.
  Future<void> connectWithToken(TokenConfig config) async {
    await _connectInternal(
      userId: config.displayName ?? 'token-user',
      successMessage: 'Token login sent',
      loginCommand: SocketCommand.tokenLogin,
      payload: <String, dynamic>{
        'token': config.token,
        if (config.displayName != null) 'displayName': config.displayName,
        'answerUrl': config.answerUrl ?? _config.answerUrl,
      },
    );
  }

  /// Convenience wrapper for starting an outbound call.
  ///
  /// This uses `flutter_webrtc` through [PeerService] to create local media,
  /// build an SDP offer, and send the invite over the signaling socket.
  Future<String> makeCall(
    String destination, {
    Map<String, String> headers = const <String, String>{},
  }) {
    return startCall(destination, headers: headers);
  }

  /// Starts an outbound call by creating a local offer and sending an invite.
  Future<String> startCall(
    String destination, {
    Map<String, String> headers = const <String, String>{},
  }) async {
    _ensureConnected();

    final String callId = DateTime.now().microsecondsSinceEpoch.toString();
    final CallSession session = _callManager.createOutgoing(
      callId: callId,
      destination: destination,
      answerUrl: _config.answerUrl,
      metadata: <String, dynamic>{'headers': headers},
    );
    _callRepository.upsert(session);

    try {
      _callManager.updateState(
        callId,
        CallStateStatus.connecting,
        message: 'Preparing local offer',
      );

      await _peerService.initialize(callId);
      final RTCSessionDescription offer = await _peerService.createOffer();

      await _socketService.send(
        SocketEnvelope(
          command: SocketCommand.invite,
          payload: InviteMessage(
            callId: callId,
            destination: destination,
            sdp: offer.sdp ?? '',
            headers: headers,
          ).toJson(),
        ),
      );

      _callManager.updateState(
        callId,
        CallStateStatus.ringing,
        message: 'Invite sent',
      );
      return callId;
    } catch (error, stackTrace) {
      _logger.error('Failed to start call: $error\n$stackTrace');
      _callManager.updateState(
        callId,
        CallStateStatus.failed,
        message: 'Failed to start outgoing call',
      );
      _emitError(
        code: 'start_call_failed',
        message: 'Unable to start the call',
        cause: error,
      );
      rethrow;
    }
  }

  /// Answers an incoming call.
  ///
  /// If the invite contained a remote SDP offer, it is applied before creating
  /// the local answer.
  Future<void> answerCall(String callId) async {
    final CallSession session = _requireCall(callId);

    try {
      await _peerService.initialize(callId);

      final String? remoteSdp = session.metadata['remoteSdp'] as String?;
      if (remoteSdp != null && remoteSdp.isNotEmpty) {
        await _peerService.setRemoteDescription(
          RTCSessionDescription(remoteSdp, 'offer'),
        );
      }

      final RTCSessionDescription answer = await _peerService.createAnswer();
      await _socketService.send(
        SocketEnvelope(
          command: SocketCommand.answer,
          payload: AnswerMessage(
            callId: callId,
            sdp: answer.sdp ?? '',
          ).toJson(),
        ),
      );

      _callManager.updateState(
        callId,
        CallStateStatus.active,
        message: 'Answer sent',
      );
    } catch (error, stackTrace) {
      _logger.error('Failed to answer call $callId: $error\n$stackTrace');
      _callManager.updateState(
        callId,
        CallStateStatus.failed,
        message: 'Failed to answer incoming call',
      );
      _emitError(
        code: 'answer_failed',
        message: 'Unable to answer call $callId',
        cause: error,
      );
      rethrow;
    }
  }

  /// Rejects an incoming call and removes it from local state.
  /// Accepts the current incoming call or a specific call when [callId] is set.
  ///
  /// The method initializes WebRTC media, applies the remote offer when
  /// available, creates an SDP answer, and sends it through the socket.
  Future<void> acceptCall([String? callId]) async {
    final String resolvedCallId = _resolveCallId(
      explicitCallId: callId,
      allowedStates: <CallStateStatus>{
        CallStateStatus.incoming,
        CallStateStatus.ringing,
      },
      actionName: 'accept',
    );
    await answerCall(resolvedCallId);
  }

  /// Rejects the current incoming call or a specific call when [callId] is set.
  ///
  /// A reject message is sent through the signaling socket and local state is
  /// updated so listeners can react immediately.
  Future<void> rejectCall([String? callId]) async {
    final String resolvedCallId = _resolveCallId(
      explicitCallId: callId,
      allowedStates: <CallStateStatus>{
        CallStateStatus.incoming,
        CallStateStatus.ringing,
      },
      actionName: 'reject',
    );
    _requireCall(resolvedCallId);

    try {
      await _socketService.send(
        SocketEnvelope(
          command: SocketCommand.reject,
          payload: ByeMessage(
            callId: resolvedCallId,
            reason: 'rejected',
          ).toJson(),
        ),
      );
      _callRepository.remove(resolvedCallId);
      _callManager.remove(resolvedCallId, message: 'Call rejected');
    } catch (error, stackTrace) {
      _logger.error(
        'Failed to reject call $resolvedCallId: $error\n$stackTrace',
      );
      _emitError(
        code: 'reject_failed',
        message: 'Unable to reject call $resolvedCallId',
        cause: error,
      );
      rethrow;
    }
  }

  /// Hangs up an active or ringing call.
  Future<void> hangup(String callId) async {
    _requireCall(callId);

    try {
      await _socketService.send(
        SocketEnvelope(
          command: SocketCommand.bye,
          payload: ByeMessage(callId: callId, reason: 'hangup').toJson(),
        ),
      );
      await _peerService.disposeCurrentCall();
      _callRepository.remove(callId);
      _callManager.remove(callId, message: 'Call ended');
    } catch (error, stackTrace) {
      _logger.error('Failed to hang up call $callId: $error\n$stackTrace');
      _emitError(
        code: 'hangup_failed',
        message: 'Unable to hang up call $callId',
        cause: error,
      );
      rethrow;
    }
  }

  /// Mutes the local microphone for the current peer connection.
  Future<void> mute(String callId) async {
    final CallSession session = _requireCall(callId);
    await _peerService.setMuted(true);
    session.muted = true;
  }

  /// Unmutes the local microphone for the current peer connection.
  Future<void> unmute(String callId) async {
    final CallSession session = _requireCall(callId);
    await _peerService.setMuted(false);
    session.muted = false;
  }

  /// Routes call audio to the speaker or earpiece.
  Future<void> setSpeakerEnabled(String callId, bool enabled) async {
    final CallSession session = _requireCall(callId);
    await _peerService.enableSpeaker(enabled);
    session.speakerEnabled = enabled;
  }

  /// Sends a DTMF signaling message for the specified call.
  Future<void> sendDtmf(String callId, String tone) async {
    _requireCall(callId);
    await _socketService.send(
      SocketEnvelope(
        command: SocketCommand.keepAlive,
        payload: <String, dynamic>{
          'type': 'dtmf',
          'callId': callId,
          'tone': tone,
        },
      ),
    );
  }

  /// Adds a remote ICE candidate to the peer connection.
  ///
  /// The same candidate is also forwarded through the signaling socket when the
  /// application wants to use this method to publish a local candidate.
  Future<void> addRemoteCandidate(
    String callId,
    RTCIceCandidate candidate,
  ) async {
    _requireCall(callId);

    try {
      await _peerService.addIceCandidate(candidate);
      await _socketService.send(
        SocketEnvelope(
          command: SocketCommand.candidate,
          payload: CandidateMessage(
            callId: callId,
            candidate: candidate.candidate ?? '',
            sdpMid: candidate.sdpMid,
            sdpMLineIndex: candidate.sdpMLineIndex,
          ).toJson(),
        ),
      );
    } catch (error, stackTrace) {
      _logger.error(
        'Failed to process ICE candidate for $callId: $error\n$stackTrace',
      );
      _emitError(
        code: 'candidate_failed',
        message: 'Unable to process ICE candidate for call $callId',
        cause: error,
      );
      rethrow;
    }
  }

  /// Creates a synthetic incoming call event for demo/testing flows.
  Future<void> simulateIncomingCall({
    required String callId,
    required String callerName,
    required String callerNumber,
    String? remoteSdp,
  }) async {
    final IncomingCall incoming = IncomingCall(
      callId: callId,
      callerName: callerName,
      callerNumber: callerNumber,
      metadata: <String, dynamic>{
        if (remoteSdp != null) 'remoteSdp': remoteSdp,
      },
    );

    final CallSession session = _callManager.createIncoming(
      incoming,
      answerUrl: _config.answerUrl,
    );
    _callRepository.upsert(session);
  }

  /// Disconnects the signaling socket and clears local call/session state.
  Future<void> disconnect() async {
    try {
      await _peerService.disposeCurrentCall();
      await _socketService.close();
    } catch (error, stackTrace) {
      _logger.error('Failed during disconnect: $error\n$stackTrace');
      _emitError(
        code: 'disconnect_failed',
        message: 'An error occurred while disconnecting',
        cause: error,
      );
      rethrow;
    } finally {
      _callManager.clear();
      _callRepository.clear();
      _sessionRepository.clear();
      _registrationState = RegistrationState.unregistered;
      _connectionState = ConnectionStateStatus.disconnected;
      _isConnected = false;
      _connectionEvents.addIfOpen(
        ConnectionEvent(
          connectionState: _connectionState,
          registrationState: _registrationState,
          message: 'Disconnected',
        ),
      );
    }
  }

  /// Optional cleanup helper if the client instance is no longer reused.
  Future<void> dispose() async {
    await disconnect();
    for (final StreamSubscription<dynamic> subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _connectionEvents.close();
    await _callEvents.close();
    await _mediaEvents.close();
    await _errorEvents.close();
  }

  // Subscribes once to the lower-level services and republishes their events.
  void _wireServices() {
    _subscriptions.add(
      _socketService.connectionEvents.listen(_handleConnectionEvent),
    );
    _subscriptions.add(
      _socketService.errorEvents.listen((ErrorEvent event) {
        if (event.code == 'socket_error') {
          _connectionState = ConnectionStateStatus.failed;
          _registrationState = RegistrationState.failed;
          _isConnected = false;
        }
        _errorEvents.addIfOpen(event);
      }),
    );
    _subscriptions.add(
      _socketService.messages.listen((SocketEnvelope envelope) async {
        try {
          await _handleSocketMessage(envelope);
        } catch (error, stackTrace) {
          _logger.error(
            'Unhandled signaling message failure: $error\n$stackTrace',
          );
          _emitError(
            code: 'signaling_message_failed',
            message:
                'Failed to process signaling message ${envelope.command.name}',
            cause: error,
          );
        }
      }),
    );
    _subscriptions.add(_callManager.callEvents.listen(_callEvents.addIfOpen));
    _subscriptions.add(_peerService.mediaEvents.listen(_mediaEvents.addIfOpen));
  }

  // Shared login implementation used by both credential styles.
  Future<void> _connectInternal({
    required String userId,
    required SocketCommand loginCommand,
    required Map<String, dynamic> payload,
    required String successMessage,
  }) async {
    if (_isConnected) {
      _logger.info('Ignoring connect request because the client is connected');
      _connectionEvents.addIfOpen(
        ConnectionEvent(
          connectionState: _connectionState,
          registrationState: _registrationState,
          message: 'Already connected',
        ),
      );
      return;
    }

    _registrationState = RegistrationState.registering;
    _sessionRepository.currentUserId = userId;
    _connectionEvents.addIfOpen(
      ConnectionEvent(
        connectionState: ConnectionStateStatus.connecting,
        registrationState: _registrationState,
        message: 'Connecting to signaling server',
      ),
    );

    try {
      await _socketService.connect();
      await _socketService.send(
        SocketEnvelope(
          command: loginCommand,
          payload: payload,
        ),
      );
      _setRegistered(successMessage);
    } catch (error, stackTrace) {
      _logger.error('Connect failed: $error\n$stackTrace');
      _registrationState = RegistrationState.failed;
      _connectionState = ConnectionStateStatus.failed;
      _isConnected = false;
      _emitError(
        code: 'connect_failed',
        message: 'Failed to connect to the signaling server',
        cause: error,
      );
      _connectionEvents.addIfOpen(
        ConnectionEvent(
          connectionState: _connectionState,
          registrationState: _registrationState,
          message: 'Connection failed',
        ),
      );
      rethrow;
    }
  }

  // Updates public state when a lower-level socket event arrives.
  void _handleConnectionEvent(ConnectionEvent event) {
    _connectionState = event.connectionState;

    if (event.connectionState == ConnectionStateStatus.connected &&
        _registrationState == RegistrationState.unregistered) {
      _isConnected = true;
    } else if (event.connectionState == ConnectionStateStatus.disconnected ||
        event.connectionState == ConnectionStateStatus.failed) {
      _isConnected = false;
      if (_registrationState == RegistrationState.registered) {
        _registrationState = RegistrationState.unregistered;
      }
    }

    _connectionEvents.addIfOpen(
      ConnectionEvent(
        connectionState: _connectionState,
        registrationState: _registrationState,
        message: event.message,
      ),
    );
  }

  // Marks the login flow as completed and notifies listeners.
  void _setRegistered(String message) {
    _registrationState = RegistrationState.registered;
    _connectionState = ConnectionStateStatus.connected;
    _isConnected = true;
    _connectionEvents.addIfOpen(
      ConnectionEvent(
        connectionState: _connectionState,
        registrationState: _registrationState,
        message: message,
      ),
    );
  }

  // Handles application-level signaling messages from the WebSocket.
  Future<void> _handleSocketMessage(SocketEnvelope envelope) async {
    switch (envelope.command) {
      case SocketCommand.incomingInvite:
        final String callId = envelope.payload['callId'] as String? ??
            DateTime.now().millisecondsSinceEpoch.toString();
        await simulateIncomingCall(
          callId: callId,
          callerName: envelope.payload['callerName'] as String? ?? 'Unknown',
          callerNumber:
              envelope.payload['callerNumber'] as String? ?? 'Unknown',
          remoteSdp: envelope.payload['sdp'] as String?,
        );
        break;

      case SocketCommand.answer:
        final String callId = envelope.payload['callId'] as String;
        final String sdp = envelope.payload['sdp'] as String? ?? '';
        await _peerService.setRemoteDescription(
          RTCSessionDescription(sdp, 'answer'),
        );
        _callManager.updateState(
          callId,
          CallStateStatus.active,
          message: 'Remote answer applied',
        );
        break;

      case SocketCommand.candidate:
        final RTCIceCandidate candidate = RTCIceCandidate(
          envelope.payload['candidate'] as String?,
          envelope.payload['sdpMid'] as String?,
          envelope.payload['sdpMLineIndex'] as int?,
        );
        await _peerService.addIceCandidate(candidate);
        break;

      case SocketCommand.bye:
      case SocketCommand.reject:
        final String callId = envelope.payload['callId'] as String;
        await _peerService.disposeCurrentCall();
        _callRepository.remove(callId);
        _callManager.remove(callId, message: 'Remote ended the call');
        break;

      case SocketCommand.ringing:
        final String callId = envelope.payload['callId'] as String;
        _callManager.updateState(
          callId,
          CallStateStatus.ringing,
          message: 'Remote is ringing',
        );
        break;

      case SocketCommand.login:
      case SocketCommand.tokenLogin:
      case SocketCommand.invite:
      case SocketCommand.keepAlive:
        // These commands are outbound requests or no-op acknowledgements here.
        break;
    }
  }

  // Emits a standardized SDK error event.
  void _emitError({
    required String code,
    required String message,
    Object? cause,
  }) {
    _errorEvents.addIfOpen(
      ErrorEvent(
        code: code,
        message: message,
        cause: cause,
      ),
    );
  }

  // Throws when a connected session is required for an operation.
  void _ensureConnected() {
    if (!_isConnected) {
      throw StateError('VobizClient is not connected');
    }
  }

  // Throws when a call cannot be found locally.
  CallSession _requireCall(String callId) {
    final CallSession? session = _callManager.getById(callId);
    if (session == null) {
      throw StateError('Call $callId not found');
    }
    return session;
  }

  // Resolves a target call for convenience APIs that can operate on the latest
  // active call when the consumer does not provide a call ID.
  String _resolveCallId({
    String? explicitCallId,
    required Set<CallStateStatus> allowedStates,
    required String actionName,
  }) {
    if (explicitCallId != null) {
      final CallSession session = _requireCall(explicitCallId);
      if (!allowedStates.contains(session.state)) {
        throw StateError(
          'Cannot $actionName call $explicitCallId while it is ${session.state.name}',
        );
      }
      return explicitCallId;
    }

    final CallSession? session = currentCall;
    if (session == null) {
      throw StateError('No call is available to $actionName');
    }

    if (!allowedStates.contains(session.state)) {
      throw StateError(
        'Cannot $actionName call ${session.callId} while it is ${session.state.name}',
      );
    }

    return session.callId;
  }
}
