import 'package:flutter/material.dart';
import 'package:vobiz_webrtc/vobiz_webrtc.dart';

class ConnectionBanner extends StatelessWidget {
  const ConnectionBanner({super.key, this.event});

  final ConnectionEvent? event;

  @override
  Widget build(BuildContext context) {
    final String text = event == null
        ? 'Disconnected'
        : '${event!.connectionState.name} / ${event!.registrationState.name}';
    return Container(
      padding: const EdgeInsets.all(12),
      color: Colors.blueGrey.shade50,
      child: Text(text),
    );
  }
}
