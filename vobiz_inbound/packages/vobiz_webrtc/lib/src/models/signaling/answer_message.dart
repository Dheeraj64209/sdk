class AnswerMessage {
  const AnswerMessage({
    required this.callId,
    required this.sdp,
  });

  final String callId;
  final String sdp;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'type': 'answer',
        'callId': callId,
        'sdp': sdp,
      };
}
