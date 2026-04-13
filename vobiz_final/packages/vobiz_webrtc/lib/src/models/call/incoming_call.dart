class IncomingCall {
  const IncomingCall({
    required this.callId,
    required this.callerName,
    required this.callerNumber,
    this.metadata = const <String, dynamic>{},
  });

  final String callId;
  final String callerName;
  final String callerNumber;
  final Map<String, dynamic> metadata;
}
