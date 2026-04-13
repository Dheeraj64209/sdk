import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../events/media_event.dart';
import '../utils/logger.dart';
import '../utils/stream_extensions.dart';
import 'audio_router.dart';
import 'ice_config.dart';
import 'media_constraints.dart';

/// Handles all `flutter_webrtc` peer-connection work for a single active call.
///
/// Responsibilities:
/// - create and configure the `RTCPeerConnection`
/// - capture the local audio stream from the microphone
/// - attach local tracks to the peer connection
/// - listen for remote media and connection state changes
/// - expose media events back to the SDK consumer
class PeerService {
  PeerService({
    required this.iceConfig,
    required this.mediaConstraints,
    AudioRouter? audioRouter,
    Logger? logger,
  })  : _audioRouter = audioRouter ?? AudioRouter(),
        _logger = logger ?? Logger();

  final IceConfig iceConfig;
  final MediaConstraints mediaConstraints;
  final AudioRouter _audioRouter;
  final Logger _logger;

  final StreamController<MediaEvent> _mediaEvents =
      StreamController<MediaEvent>.broadcast();
  final StreamController<RTCIceCandidate> _iceCandidates =
      StreamController<RTCIceCandidate>.broadcast();

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  String? _activeCallId;
  bool _localAudioAttached = false;
  bool _remoteDescriptionApplied = false;
  final List<RTCIceCandidate> _pendingRemoteCandidates = <RTCIceCandidate>[];

  /// Emits local/remote media lifecycle updates.
  Stream<MediaEvent> get mediaEvents => _mediaEvents.stream;

  /// Emits local ICE candidates so signaling can forward them to the far end.
  Stream<RTCIceCandidate> get iceCandidates => _iceCandidates.stream;

  /// Current peer connection instance, if initialized.
  RTCPeerConnection? get peerConnection => _peerConnection;

  /// Current local media stream captured from the microphone.
  MediaStream? get localStream => _localStream;

  /// Current remote media stream received from the far end.
  MediaStream? get remoteStream => _remoteStream;

  /// Creates a new peer connection for the given call and wires listeners.
  ///
  /// If an old call is still active, it is cleaned up first so stale tracks and
  /// connection listeners do not leak into the new session.
  Future<RTCPeerConnection> createPeerConnection(String callId) async {
    if (_peerConnection != null ||
        _localStream != null ||
        _remoteStream != null) {
      await disposeCurrentCall();
    }

    _activeCallId = callId;
    _remoteDescriptionApplied = false;
    _pendingRemoteCandidates.clear();

    try {
      final RTCPeerConnection connection =
          await flutterWebRTCCreatePeerConnection(
        iceConfig.toRtcConfiguration(),
        <String, dynamic>{},
      );

      _peerConnection = connection;
      _wirePeerConnectionListeners(connection, callId);

      _mediaEvents.addIfOpen(
        MediaEvent(
          callId: callId,
          message: 'Peer connection created',
        ),
      );

      return connection;
    } catch (error, stackTrace) {
      _logger.error(
        'Failed to create peer connection for $callId: $error\n$stackTrace',
      );
      _activeCallId = null;
      rethrow;
    }
  }

  /// Convenience entry point used by the client before offer/answer exchange.
  ///
  /// The flow is:
  /// 1. create the `RTCPeerConnection`
  /// 2. get microphone audio with `getUserMedia`
  /// 3. attach each local audio track to the connection
  Future<void> initialize(String callId) async {
    await createPeerConnection(callId);
    await attachLocalAudioStream(callId);
  }

  /// Captures the local microphone stream and attaches it to the connection.
  ///
  /// This uses the existing [MediaConstraints], which default to audio-only.
  Future<MediaStream> attachLocalAudioStream(String callId) async {
    final RTCPeerConnection connection = _requirePeer();

    if (_localAudioAttached && _localStream != null) {
      return _localStream!;
    }

    try {
      final MediaStream stream = await navigator.mediaDevices.getUserMedia(
        mediaConstraints.toWebRtcConstraints(),
      );

      _localStream = stream;

      for (final MediaStreamTrack track in stream.getAudioTracks()) {
        await connection.addTrack(track, stream);
      }

      _localAudioAttached = true;
      _mediaEvents.addIfOpen(
        MediaEvent(
          callId: callId,
          localStream: _localStream,
          remoteStream: _remoteStream,
          message: 'Local audio stream attached',
        ),
      );

      return stream;
    } catch (error, stackTrace) {
      _logger.error(
        'Failed to attach local audio for $callId: $error\n$stackTrace',
      );
      _localAudioAttached = false;
      rethrow;
    }
  }

  /// Creates an SDP offer after local media has been attached.
  Future<RTCSessionDescription> createOffer() async {
    final RTCPeerConnection peer = _requirePeer();
    final RTCSessionDescription offer = await peer.createOffer(
      <String, dynamic>{
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': false,
      },
    );
    await peer.setLocalDescription(offer);
    _emitMediaMessage('Local offer created');
    return offer;
  }

  /// Creates an SDP answer after the remote offer has been applied.
  Future<RTCSessionDescription> createAnswer() async {
    final RTCPeerConnection peer = _requirePeer();
    final RTCSessionDescription answer = await peer.createAnswer(
      <String, dynamic>{
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': false,
      },
    );
    await peer.setLocalDescription(answer);
    _emitMediaMessage('Local answer created');
    return answer;
  }

  /// Creates an offer and returns it for signaling.
  ///
  /// This is the outbound flow:
  /// 1. ensure the peer connection exists
  /// 2. ensure local audio is attached
  /// 3. create and store the local offer
  /// 4. return the SDP so the signaling layer can send it
  Future<RTCSessionDescription> createOfferExchange() async {
    if (_peerConnection == null) {
      throw StateError('Peer connection has not been created');
    }
    if (!_localAudioAttached) {
      await attachLocalAudioStream(_activeCallId ?? 'unknown');
    }
    return createOffer();
  }

  /// Accepts a remote offer and generates the local answer.
  ///
  /// This is the inbound flow:
  /// 1. ensure local media is ready
  /// 2. apply the remote offer
  /// 3. create and store the local answer
  /// 4. return the SDP so signaling can send it back
  Future<RTCSessionDescription> handleRemoteOffer(
    RTCSessionDescription offer,
  ) async {
    if (_peerConnection == null) {
      throw StateError('Peer connection has not been created');
    }
    if (!_localAudioAttached) {
      await attachLocalAudioStream(_activeCallId ?? 'unknown');
    }
    await setRemoteDescription(offer);
    return createAnswer();
  }

  /// Applies a remote answer to complete an outbound offer/answer exchange.
  Future<void> handleRemoteAnswer(RTCSessionDescription answer) async {
    await setRemoteDescription(answer);
    _emitMediaMessage('Remote answer applied');
  }

  /// Applies the remote SDP description received from signaling.
  Future<void> setRemoteDescription(RTCSessionDescription description) async {
    await _requirePeer().setRemoteDescription(description);
    _remoteDescriptionApplied = true;
    await _flushPendingRemoteCandidates();
    _emitMediaMessage('Remote description applied');
  }

  /// Adds a remote ICE candidate received from signaling.
  Future<void> addIceCandidate(RTCIceCandidate candidate) async {
    if (!_remoteDescriptionApplied) {
      _pendingRemoteCandidates.add(candidate);
      _emitMediaMessage('Remote ICE candidate queued');
      return;
    }

    await _requirePeer().addCandidate(candidate);
    _emitMediaMessage('Remote ICE candidate added');
  }

  /// Enables or disables the microphone tracks in the local stream.
  Future<void> setMuted(bool muted) async {
    final MediaStream? stream = _localStream;
    if (stream == null) {
      return;
    }

    for (final MediaStreamTrack track in stream.getAudioTracks()) {
      track.enabled = !muted;
    }

    _emitMediaMessage(muted ? 'Microphone muted' : 'Microphone unmuted');
  }

  /// Switches audio output routing using the platform audio helper.
  Future<void> enableSpeaker(bool enabled) async {
    await _audioRouter.enableSpeaker(enabled);
    _emitMediaMessage(enabled ? 'Speaker enabled' : 'Speaker disabled');
  }

  /// Releases peer-connection resources, local media, and remote media.
  Future<void> disposeCurrentCall() async {
    final MediaStream? localStream = _localStream;
    final MediaStream? remoteStream = _remoteStream;
    final RTCPeerConnection? peerConnection = _peerConnection;
    final String callId = _activeCallId ?? 'unknown';

    if (localStream != null) {
      for (final MediaStreamTrack track in localStream.getTracks()) {
        await track.stop();
      }
      await localStream.dispose();
    }

    if (remoteStream != null) {
      for (final MediaStreamTrack track in remoteStream.getTracks()) {
        await track.stop();
      }
      await remoteStream.dispose();
    }

    if (peerConnection != null) {
      await peerConnection.close();
    }

    _peerConnection = null;
    _localStream = null;
    _remoteStream = null;
    _activeCallId = null;
    _localAudioAttached = false;
    _remoteDescriptionApplied = false;
    _pendingRemoteCandidates.clear();

    _mediaEvents.addIfOpen(
      MediaEvent(
        callId: callId,
        message: 'Peer resources released',
      ),
    );
  }

  /// Closes the media event stream when the service is no longer reused.
  Future<void> dispose() async {
    await disposeCurrentCall();
    await _iceCandidates.close();
    await _mediaEvents.close();
  }

  // Registers all peer-connection callbacks that keep SDK state observable.
  void _wirePeerConnectionListeners(
    RTCPeerConnection connection,
    String callId,
  ) {
    connection.onTrack = (RTCTrackEvent event) {
      if (event.streams.isEmpty) {
        return;
      }

      _remoteStream = event.streams.first;
      _mediaEvents.addIfOpen(
        MediaEvent(
          callId: callId,
          localStream: _localStream,
          remoteStream: _remoteStream,
          message: 'Remote stream attached',
        ),
      );
    };

    connection.onIceCandidate = (RTCIceCandidate candidate) {
      _logger.info('ICE candidate generated for $callId');
      _iceCandidates.addIfOpen(candidate);
      _mediaEvents.addIfOpen(
        MediaEvent(
          callId: callId,
          localStream: _localStream,
          remoteStream: _remoteStream,
          message: 'Local ICE candidate generated',
        ),
      );
    };

    connection.onConnectionState = (RTCPeerConnectionState state) {
      _logger.info('Peer connection state for $callId: $state');
      _mediaEvents.addIfOpen(
        MediaEvent(
          callId: callId,
          localStream: _localStream,
          remoteStream: _remoteStream,
          message: 'Peer connection state changed to $state',
        ),
      );
    };

    connection.onIceConnectionState = (RTCIceConnectionState state) {
      _logger.info('ICE connection state for $callId: $state');
      _mediaEvents.addIfOpen(
        MediaEvent(
          callId: callId,
          localStream: _localStream,
          remoteStream: _remoteStream,
          message: 'ICE connection state changed to $state',
        ),
      );
    };
  }

  // Adds any remote candidates that arrived before the remote SDP was ready.
  Future<void> _flushPendingRemoteCandidates() async {
    if (!_remoteDescriptionApplied || _pendingRemoteCandidates.isEmpty) {
      return;
    }

    final RTCPeerConnection peer = _requirePeer();
    for (final RTCIceCandidate candidate
        in List<RTCIceCandidate>.from(_pendingRemoteCandidates)) {
      await peer.addCandidate(candidate);
    }
    _pendingRemoteCandidates.clear();
    _emitMediaMessage('Queued remote ICE candidates applied');
  }

  // Emits a lightweight media event tied to the current call state.
  void _emitMediaMessage(String message) {
    _mediaEvents.addIfOpen(
      MediaEvent(
        callId: _activeCallId ?? 'unknown',
        localStream: _localStream,
        remoteStream: _remoteStream,
        message: message,
      ),
    );
  }

  // Guards all operations that require an initialized peer connection.
  RTCPeerConnection _requirePeer() {
    final RTCPeerConnection? peer = _peerConnection;
    if (peer == null) {
      throw StateError('PeerService is not initialized');
    }
    return peer;
  }
}

/// Wraps `createPeerConnection` so the service code stays explicit about the
/// `flutter_webrtc` entry point it uses.
Future<RTCPeerConnection> flutterWebRTCCreatePeerConnection(
  Map<String, dynamic> configuration,
  Map<String, dynamic> constraints,
) {
  return createPeerConnection(configuration, constraints);
}
