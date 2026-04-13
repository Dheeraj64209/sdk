class OutgoingCall {
  const OutgoingCall({
    required this.callId,
    required this.destination,
    this.metadata = const <String, dynamic>{},
  });

  final String callId;
  final String destination;
  final Map<String, dynamic> metadata;
}
