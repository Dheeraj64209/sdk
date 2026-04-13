class ByeMessage {
  const ByeMessage({
    required this.callId,
    this.reason,
  });

  final String callId;
  final String? reason;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'type': 'bye',
        'callId': callId,
        if (reason != null) 'reason': reason,
      };
}
