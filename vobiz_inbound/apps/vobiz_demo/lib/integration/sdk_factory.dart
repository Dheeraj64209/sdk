import 'package:vobiz_webrtc/vobiz_webrtc.dart';

class SdkFactory {
  const SdkFactory();

  static const _answerUrl = String.fromEnvironment(
    'VOBIZ_ANSWER_URL',
    defaultValue: 'https://example.com/answer',
  );

  VobizClient createClient() {
    return VobizClient(
      config: const SdkConfig(
        socketUrl: 'wss://sip.vobiz.ai:7443',
        answerUrl: _answerUrl,
        autoReconnect: true,
        debug: true,
      ),
    );
  }
}
