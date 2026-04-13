class InviteMessage {
  const InviteMessage({
    required this.callId,
    required this.destination,
    required this.sdp,
    this.headers = const <String, String>{},
  });

  final String callId;
  final String destination;
  final String sdp;
  final Map<String, String> headers;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'type': 'invite',
        'callId': callId,
        'destination': destination,
        'sdp': sdp,
        'headers': headers,
      };
}
