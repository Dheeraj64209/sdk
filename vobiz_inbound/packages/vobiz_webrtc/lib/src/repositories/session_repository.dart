class SessionRepository {
  String? currentSessionId;
  String? currentUserId;

  void clear() {
    currentSessionId = null;
    currentUserId = null;
  }
}
