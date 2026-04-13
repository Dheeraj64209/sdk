import '../calls/call_session.dart';
import '../state/call_state.dart';
import 'sdk_event.dart';

class CallEvent extends SdkEvent {
  CallEvent({
    required this.callId,
    required this.state,
    this.session,
    this.message,
    super.timestamp,
  });

  final String callId;
  final CallStateStatus state;
  final CallSession? session;
  final String? message;
}
