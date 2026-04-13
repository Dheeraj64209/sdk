import 'package:flutter_webrtc/flutter_webrtc.dart';

class AudioRouter {
  Future<void> enableSpeaker(bool enabled) async {
    await Helper.setSpeakerphoneOn(enabled);
  }
}
