import 'package:flutter_webrtc/flutter_webrtc.dart';

class PermissionService {
  Future<bool> requestMicrophonePermission() async {
    MediaStream? stream;
    try {
      stream = await navigator.mediaDevices.getUserMedia(<String, dynamic>{
        'audio': true,
        'video': false,
      });
      return true;
    } catch (_) {
      return false;
    } finally {
      await stream?.dispose();
    }
  }
}
