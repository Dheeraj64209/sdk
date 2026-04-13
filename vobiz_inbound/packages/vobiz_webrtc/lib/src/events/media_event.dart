import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'sdk_event.dart';

class MediaEvent extends SdkEvent {
  MediaEvent({
    required this.callId,
    this.localStream,
    this.remoteStream,
    this.message,
    super.timestamp,
  });

  final String callId;
  final MediaStream? localStream;
  final MediaStream? remoteStream;
  final String? message;
}
