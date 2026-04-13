import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import '../utils/logger.dart';

class PeerService {
  static const String _turnUrls = String.fromEnvironment(
    'VOBIZ_TURN_URLS',
    defaultValue: '',
  );
  static const String _turnUsername = String.fromEnvironment(
    'VOBIZ_TURN_USERNAME',
    defaultValue: '',
  );
  static const String _turnPassword = String.fromEnvironment(
    'VOBIZ_TURN_PASSWORD',
    defaultValue: '',
  );

  rtc.RTCPeerConnection? _pc;
  rtc.MediaStream? _localStream;
  String? _storedOfferSdp;

  final List<rtc.RTCIceCandidate> _iceCandidateQueue = [];
  bool _remoteDescriptionSet = false;

  bool get hasRemoteDescription => _remoteDescriptionSet;

  void Function(rtc.RTCIceCandidate candidate)? onIceCandidate;
  void Function(rtc.MediaStream stream)? onRemoteStream;
  void Function()? onConnected;
  void Function()? onDisconnected;

  Future<void> createPeerConnection() async {
    try {
      await _disposePeerConnection();
      _remoteDescriptionSet = false;
      _iceCandidateQueue.clear();

      final config = <String, dynamic>{
        'iceServers': _buildIceServers(),
        'sdpSemantics': 'unified-plan',
        'bundlePolicy': 'balanced',
        'rtcpMuxPolicy': 'require',
        'iceTransportPolicy': 'all',
        'iceCandidatePoolSize': 4,
      };

      _pc = await rtc.createPeerConnection(config, {});
      _attachListeners();
      Log.info('WebRTC', 'Peer connection created');
    } catch (e) {
      Log.error('WebRTC', 'Failed to create peer connection: $e');
      rethrow;
    }
  }

  Future<void> attachLocalAudioStream() async {
    try {
      if (_pc == null) {
        throw StateError(
            'Peer connection is null. Call createPeerConnection() first.');
      }

      _localStream ??= await rtc.navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': false,
      });

      for (final track in _localStream!.getAudioTracks()) {
        await _pc!.addTrack(track, _localStream!);
      }

      Log.info('WebRTC', 'Local audio stream attached');
    } catch (e) {
      Log.error('WebRTC', 'Failed to get microphone: $e');
      rethrow;
    }
  }

  Future<String> createOffer() async {
    try {
      if (_pc == null) {
        throw StateError(
            'Peer connection is null. Call createPeerConnection() first.');
      }

      final offer = await _pc!.createOffer({
        'mandatory': {
          'OfferToReceiveAudio': true,
          'OfferToReceiveVideo': false,
        },
      });

      await _pc!.setLocalDescription(offer);
      await _waitForIceGathering();
      final local = await _pc!.getLocalDescription();

      Log.info('WebRTC', 'Offer created');
      return local?.sdp ?? offer.sdp ?? '';
    } catch (e) {
      Log.error('WebRTC', 'Failed to create offer: $e');
      rethrow;
    }
  }

  Future<void> storeRemoteOffer(String offerSdp) async {
    print('📦 [PEER] storeRemoteOffer called');
    print('📦 [PEER] Input SDP length: ${offerSdp.length}');
    final sanitized = _sanitizeSdp(offerSdp);
    print('📦 [PEER] Sanitized SDP length: ${sanitized.length}');
    _ensureLikelyValidOffer(sanitized);
    _storedOfferSdp = sanitized;
    print('📦 [PEER] _storedOfferSdp set, length: ${_storedOfferSdp?.length}');

    Log.info(
      'WebRTC',
      'Stored remote offer (length=${sanitized.length}, startsWithV=${sanitized.startsWith('v=0')})',
    );
  }

  Future<String> createAnswerFromStoredOffer() async {
    print('📦 [PEER] createAnswerFromStoredOffer called');
    print('📦 [PEER] _storedOfferSdp is null: ${_storedOfferSdp == null}');
    print('📦 [PEER] _storedOfferSdp length: ${_storedOfferSdp?.length ?? 0}');
    final offer = _storedOfferSdp;
    if (offer == null || offer.trim().isEmpty) {
      throw StateError(
          'No stored offer SDP. storeRemoteOffer() must run before answer().');
    }
    print('📦 [PEER] Calling handleRemoteOffer with offer length: ${offer.length}');

    final answer = await handleRemoteOffer(offer);
    _storedOfferSdp = null;
    return answer;
  }

  Future<String> handleRemoteOffer(String offerSdp) async {
    try {
      if (_pc == null) {
        throw StateError(
            'Peer connection is null. Call createPeerConnection() first.');
      }

      final sanitized = _sanitizeSdp(offerSdp);
      _ensureLikelyValidOffer(sanitized);

      await _setRemoteDescriptionWithRetry(sanitized, 'offer');

      _remoteDescriptionSet = true;
      await _drainIceCandidateQueue();

      final answer = await _pc!.createAnswer({
        'mandatory': {
          'OfferToReceiveAudio': true,
          'OfferToReceiveVideo': false,
        },
      });

      await _pc!.setLocalDescription(answer);
      await _waitForIceGathering();
      final local = await _pc!.getLocalDescription();

      Log.info('WebRTC', 'Answer created');
      return local?.sdp ?? answer.sdp ?? '';
    } catch (e) {
      Log.error('WebRTC', 'Failed to handle remote offer: $e');
      rethrow;
    }
  }

  Future<void> handleRemoteAnswer(String answerSdp) async {
    try {
      if (_pc == null) {
        throw StateError(
            'Peer connection is null. Call createPeerConnection() first.');
      }

      final sanitized = _sanitizeSdp(answerSdp);
      await _setRemoteDescriptionWithRetry(sanitized, 'answer');

      _remoteDescriptionSet = true;
      await _drainIceCandidateQueue();
      Log.info('WebRTC', 'Remote answer applied');
    } catch (e) {
      Log.error('WebRTC', 'Failed to apply remote answer: $e');
      rethrow;
    }
  }

  Future<void> addIceCandidate(rtc.RTCIceCandidate candidate) async {
    if (_remoteDescriptionSet && _pc != null) {
      await _pc!.addCandidate(candidate);
    } else {
      _iceCandidateQueue.add(candidate);
    }
  }

  Future<void> dispose() async {
    await _disposePeerConnection();
    _storedOfferSdp = null;
  }

  Future<void> disposeAll() async {
    await _disposePeerConnection();
    _storedOfferSdp = null;
    _localStream?.getTracks().forEach((t) => t.stop());
    await _localStream?.dispose();
    _localStream = null;
  }

  void _attachListeners() {
    final pc = _pc!;

    pc.onIceCandidate = (candidate) {
      onIceCandidate?.call(candidate);
    };

    pc.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        Log.info('WebRTC', 'Remote audio stream received');
        onRemoteStream?.call(event.streams.first);
      }
    };

    pc.onConnectionState = (state) {
      if (state == rtc.RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        Log.info('WebRTC', 'Peer connected');
        onConnected?.call();
      } else if (state ==
              rtc.RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state ==
              rtc.RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        Log.warn('WebRTC', 'Peer connection lost: $state');
        onDisconnected?.call();
      }
    };
  }

  Future<void> _waitForIceGathering() async {
    if (_pc == null) return;

    const pollInterval = Duration(milliseconds: 100);
    const timeout = Duration(seconds: 8);
    final deadline = DateTime.now().add(timeout);

    while (DateTime.now().isBefore(deadline)) {
      await Future.delayed(pollInterval);
      if (_pc == null) return;

      final state = await _pc!.getIceGatheringState();
      if (state == rtc.RTCIceGatheringState.RTCIceGatheringStateComplete) {
        return;
      }
    }

    final localDescription = await _pc!.getLocalDescription();
    final candidateCount = RegExp(r'^a=candidate:', multiLine: true)
        .allMatches(localDescription?.sdp ?? '')
        .length;
    Log.warn(
      'WebRTC',
      'ICE gathering timeout, proceeding with $candidateCount candidates',
    );
  }

  Future<void> _drainIceCandidateQueue() async {
    if (_pc == null) return;
    for (final c in _iceCandidateQueue) {
      await _pc!.addCandidate(c);
    }
    _iceCandidateQueue.clear();
  }

  Future<void> _disposePeerConnection() async {
    if (_pc != null) {
      await _pc!.close();
      _pc = null;
    }
    _iceCandidateQueue.clear();
    _remoteDescriptionSet = false;
  }

  List<Map<String, dynamic>> _buildIceServers() {
    final iceServers = <Map<String, dynamic>>[
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {'urls': 'stun:stun2.l.google.com:19302'},
      {'urls': 'stun:stun3.l.google.com:19302'},
    ];

    if (_turnUrls.trim().isNotEmpty) {
      iceServers.add({
        'urls': _turnUrls
            .split(',')
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .toList(),
        if (_turnUsername.trim().isNotEmpty) 'username': _turnUsername.trim(),
        if (_turnPassword.trim().isNotEmpty) 'credential': _turnPassword.trim(),
      });
    }

    return iceServers;
  }

  String _sanitizeSdp(String sdp) {
    var out = sdp;
    if (out.startsWith('\uFEFF')) {
      out = out.substring(1);
    }

    // Remove only truly invalid control chars, keep CR/LF/TAB intact.
    out = out.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');

    // Canonicalize to CRLF and ensure final CRLF for strict native parsers.
    out = out.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    out = out.split('\n').join('\r\n');
    if (!out.endsWith('\r\n')) {
      out = '$out\r\n';
    }
    return out;
  }

  void _ensureLikelyValidOffer(String offerSdp) {
    if (offerSdp.trim().isEmpty) {
      throw StateError('Remote offer SDP is empty after sanitization');
    }
    if (!offerSdp.contains('v=0')) {
      throw StateError('Remote offer SDP missing v=0 line');
    }
    if (!offerSdp.contains('m=audio')) {
      throw StateError('Remote offer SDP missing m=audio line');
    }
  }

  Future<void> _setRemoteDescriptionWithRetry(String sdp, String type) async {
    if (_pc == null) {
      throw StateError(
          'Peer connection is null. Call createPeerConnection() first.');
    }

    print('🔧 [PEER] _setRemoteDescriptionWithRetry called');
    print('🔧 [PEER] SDP type: $type');
    print('🔧 [PEER] SDP length: ${sdp.length}');
    print('🔧 [PEER] SDP first 100 chars: ${sdp.substring(0, sdp.length > 100 ? 100 : sdp.length)}');
    print('🔧 [PEER] SDP is null: ${sdp == null}');
    print('🔧 [PEER] SDP isEmpty: ${sdp.isEmpty}');

    final candidates = <String>[
      sdp,
      _sanitizeSdp(sdp),
      sdp.replaceAll('\r\n', '\n'),
    ];

    Object? lastError;
    for (var i = 0; i < candidates.length; i++) {
      final candidate = candidates[i];
      try {
        final desc = rtc.RTCSessionDescription(candidate, type);
        print(
          '🔧 [PEER] Try #${i + 1}: sdp=${desc.sdp?.length ?? "null"}, type=${desc.type}',
        );
        await _pc!.setRemoteDescription(desc);
        print('🔧 [PEER] setRemoteDescription SUCCESS on try #${i + 1}');
        return;
      } catch (e) {
        lastError = e;
        print('🔧 [PEER] Try #${i + 1} failed: $e');
      }
    }

    throw lastError ??
        StateError('setRemoteDescription failed with unknown error');
  }
}
