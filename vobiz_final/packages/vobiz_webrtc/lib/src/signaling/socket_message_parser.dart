import 'dart:convert';

import 'socket_protocol.dart';

class SocketMessageParser {
  SocketEnvelope parse(dynamic raw) {
    final Map<String, dynamic> json = raw is String
        ? jsonDecode(raw) as Map<String, dynamic>
        : (raw as Map).cast<String, dynamic>();

    final String commandName = json['command'] as String? ?? 'keepAlive';
    final SocketCommand command = SocketCommand.values.firstWhere(
      (SocketCommand value) => value.name == commandName,
      orElse: () => SocketCommand.keepAlive,
    );

    return SocketEnvelope(
      command: command,
      payload: (json['payload'] as Map?)?.cast<String, dynamic>() ??
          <String, dynamic>{},
    );
  }
}
