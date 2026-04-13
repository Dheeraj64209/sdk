class CandidateMessage {
  const CandidateMessage({
    required this.callId,
    required this.candidate,
    required this.sdpMid,
    required this.sdpMLineIndex,
  });

  final String callId;
  final String candidate;
  final String? sdpMid;
  final int? sdpMLineIndex;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'type': 'candidate',
        'callId': callId,
        'candidate': candidate,
        'sdpMid': sdpMid,
        'sdpMLineIndex': sdpMLineIndex,
      };
}
