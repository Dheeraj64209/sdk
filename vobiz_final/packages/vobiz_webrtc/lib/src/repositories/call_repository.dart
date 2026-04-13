import '../calls/call_session.dart';

class CallRepository {
  final Map<String, CallSession> _calls = <String, CallSession>{};

  List<CallSession> get all => _calls.values.toList(growable: false);

  CallSession? getById(String callId) => _calls[callId];

  void upsert(CallSession session) {
    _calls[session.callId] = session;
  }

  void remove(String callId) {
    _calls.remove(callId);
  }

  void clear() {
    _calls.clear();
  }
}
