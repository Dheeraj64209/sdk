import '../models/call/call_stats.dart';
import '../state/call_state.dart';
import 'call_actions.dart';

class CallSession {
  CallSession({
    required this.callId,
    required this.remoteIdentity,
    required this.isIncoming,
    required this.answerUrl,
    this.state = CallStateStatus.idle,
    Map<String, dynamic> metadata = const <String, dynamic>{},
    this.stats = const CallStats(),
  }) : metadata = Map<String, dynamic>.from(metadata);

  final String callId;
  final String remoteIdentity;
  final bool isIncoming;
  final String? answerUrl;
  final Map<String, dynamic> metadata;
  CallStateStatus state;
  CallStats stats;
  bool muted = false;
  bool speakerEnabled = false;

  CallActions get actions {
    switch (state) {
      case CallStateStatus.incoming:
        return const CallActions(canAnswer: true, canReject: true);
      case CallStateStatus.connecting:
      case CallStateStatus.ringing:
      case CallStateStatus.active:
        return const CallActions(
          canHangup: true,
          canMute: true,
          canSendDtmf: true,
        );
      default:
        return const CallActions();
    }
  }
}
