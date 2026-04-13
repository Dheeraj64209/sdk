import '../webrtc/ice_config.dart';
import '../webrtc/media_constraints.dart';

class SdkConfig {
  const SdkConfig({
    this.socketUrl,
    this.answerUrl,
    this.autoReconnect = true,
    this.debug = false,
    this.iceConfig = const IceConfig(),
    this.mediaConstraints = const MediaConstraints(),
  });

  final String? socketUrl;
  final String? answerUrl;
  final bool autoReconnect;
  final bool debug;
  final IceConfig iceConfig;
  final MediaConstraints mediaConstraints;
}
