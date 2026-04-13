// lib/screens/incall_screen.dart
// In-call screen — status text + end call button.

import 'package:flutter/material.dart';
import '../client/vobiz_client.dart';

class InCallScreen extends StatelessWidget {
  final VobizClient client;
  const InCallScreen({super.key, required this.client});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<VobizState>(
      stream: client.stream,
      initialData: client.state,
      builder: (context, snapshot) {
        final state = snapshot.data!;

        return Scaffold(
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [

                Text(
                  _callStatusText(state.call),
                  style: const TextStyle(fontSize: 20),
                ),
                const SizedBox(height: 48),

                ElevatedButton(
                  onPressed: () => client.hangup(),
                  child: const Text('End Call'),
                ),

              ],
            ),
          ),
        );
      },
    );
  }

  String _callStatusText(CallState call) {
    switch (call) {
      case CallState.calling: return 'Calling...';
      case CallState.ringing: return 'Ringing...';
      case CallState.inCall:  return 'In Call';
      default:                return '';
    }
  }
}
