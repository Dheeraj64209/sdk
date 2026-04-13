class IceServerConfig {
  const IceServerConfig({
    required this.urls,
    this.username,
    this.credential,
  });

  final List<String> urls;
  final String? username;
  final String? credential;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'urls': urls,
        if (username != null) 'username': username,
        if (credential != null) 'credential': credential,
      };
}

class IceConfig {
  const IceConfig({
    this.servers = const <IceServerConfig>[
      IceServerConfig(urls: <String>['stun:stun.l.google.com:19302']),
    ],
  });

  final List<IceServerConfig> servers;

  Map<String, dynamic> toRtcConfiguration() => <String, dynamic>{
        'iceServers': servers.map((IceServerConfig e) => e.toJson()).toList(),
      };
}
