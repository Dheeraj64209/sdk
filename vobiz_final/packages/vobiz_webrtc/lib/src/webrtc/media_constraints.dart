class MediaConstraints {
  const MediaConstraints({
    this.audio = true,
    this.video = false,
    this.echoCancellation = true,
    this.noiseSuppression = true,
    this.autoGainControl = true,
  });

  final bool audio;
  final bool video;
  final bool echoCancellation;
  final bool noiseSuppression;
  final bool autoGainControl;

  Map<String, dynamic> toWebRtcConstraints() => <String, dynamic>{
        'audio': audio
            ? <String, dynamic>{
                'echoCancellation': echoCancellation,
                'noiseSuppression': noiseSuppression,
                'autoGainControl': autoGainControl,
              }
            : false,
        'video': video,
      };
}
