// lib/services/peer_service.dart
//
// Minimal WebRTC peer service using flutter_webrtc.
// Audio-only. Aligned with the Vobiz web app call flow.

import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import '../utils/logger.dart';

class PeerService {
  rtc.RTCPeerConnection? _pc;
  rtc.MediaStream? _localStream;
  String? _storedOfferSdp;

  final List<rtc.RTCIceCandidate> _iceCandidateQueue = [];
  bool _remoteDescriptionSet = false;

  bool get hasRemoteDescription => _remoteDescriptionSet;

  // Callbacks set by VobizClient
  void Function(rtc.RTCIceCandidate candidate)? onIceCandidate;
  void Function(rtc.MediaStream stream)? onRemoteStream;
  void Function()? onConnected;
  void Function()? onDisconnected;

  // ── Step 1: Create peer connection ────────────────────────────────────────

  Future<void> createPeerConnection() async {
    try {
      await _disposePeerConnection();
      _remoteDescriptionSet = false;
      _iceCandidateQueue.clear();

      final config = <String, dynamic>{
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
          {'urls': 'stun:stun1.l.google.com:19302'},
        ],
        'sdpSemantics': 'unified-plan',
      };

      _pc = await rtc.createPeerConnection(config, {});
      _attachListeners();
      Log.info('WebRTC', 'Peer connection created');
    } catch (e) {
      Log.error('WebRTC', 'Failed to create peer connection: $e');
      rethrow;
    }
  }

  // ── Step 2: Acquire microphone ────────────────────────────────────────────

  Future<void> attachLocalAudioStream() async {
    try {
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

  // ── Step 3a: Outbound — create offer SDP ──────────────────────────────────

  Future<String> createOffer() async {
    try {
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
      return local?.sdp ?? offer.sdp!;
    } catch (e) {
      Log.error('WebRTC', 'Failed to create offer: $e');
      rethrow;
    }
  }

  // ── Step 3b: Inbound — store remote offer (do NOT answer yet) ─────────────
  // Called when INVITE arrives. Answer is created only when user taps Accept.

  Future<void> storeRemoteOffer(String offerSdp) async {
    _storedOfferSdp = offerSdp;
  }

  // ── Step 3c: Inbound — create answer from stored offer ────────────────────
  // Called by VobizClient.answer() after the user taps Accept.

  Future<String> createAnswerFromStoredOffer() async {
    if (_storedOfferSdp == null) {
      throw StateError(
          'No stored offer SDP — storeRemoteOffer() must be called first');
    }
    final answer = await handleRemoteOffer(_storedOfferSdp!);
    _storedOfferSdp = null;
    return answer;
  }

  // ── Internal: set remote offer + create answer ────────────────────────────

  Future<String> handleRemoteOffer(String offerSdp) async {
    try {
      await _pc!
          .setRemoteDescription(rtc.RTCSessionDescription(offerSdp, 'offer'));
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
      return local?.sdp ?? answer.sdp!;
    } catch (e) {
      Log.error('WebRTC', 'Failed to handle remote offer: $e');
      rethrow;
    }
  }

  // ── Step 4: Outbound — apply remote answer from 200 OK ────────────────────

  Future<void> handleRemoteAnswer(String answerSdp) async {
    try {
      await _pc!
          .setRemoteDescription(rtc.RTCSessionDescription(answerSdp, 'answer'));
      _remoteDescriptionSet = true;
      await _drainIceCandidateQueue();
      Log.info('WebRTC', 'Remote answer applied');
    } catch (e) {
      Log.error('WebRTC', 'Failed to apply remote answer: $e');
      rethrow;
    }
  }

  // ── ICE candidate (trickle-ICE) ───────────────────────────────────────────

  Future<void> addIceCandidate(rtc.RTCIceCandidate candidate) async {
    if (_remoteDescriptionSet && _pc != null) {
      await _pc!.addCandidate(candidate);
    } else {
      _iceCandidateQueue.add(candidate);
    }
  }

  // ── Dispose (end of call) ─────────────────────────────────────────────────

  Future<void> dispose() async {
    await _disposePeerConnection();
    _storedOfferSdp = null;
    // _localStream kept alive for next call
  }

  /// Full teardown — also releases the microphone.
  Future<void> disposeAll() async {
    await _disposePeerConnection();
    _storedOfferSdp = null;
    _localStream?.getTracks().forEach((t) => t.stop());
    await _localStream?.dispose();
    _localStream = null;
  }

  // ── Private helpers ───────────────────────────────────────────────────────

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
        Log.info('WebRTC', 'Peer connected — media flowing');
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
    if (_pc == null) {
      return;
    }
    const pollInterval = Duration(milliseconds: 100);
    const timeout = Duration(seconds: 3);
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      await Future.delayed(pollInterval);
      if (_pc == null) {
        return;
      }
      final state = await _pc!.getIceGatheringState();
      if (state == rtc.RTCIceGatheringState.RTCIceGatheringStateComplete) {
        return;
      }
    }
    Log.warn(
        'WebRTC', 'ICE gathering timeout — proceeding with partial candidates');
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
}
