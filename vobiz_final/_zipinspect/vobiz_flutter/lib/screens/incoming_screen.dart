// lib/screens/incoming_screen.dart
// Incoming call screen — caller ID + accept/reject buttons.

import 'package:flutter/material.dart';
import '../client/vobiz_client.dart';

class IncomingScreen extends StatelessWidget {
  final VobizClient client;
  final String      callerId;

  const IncomingScreen({
    super.key,
    required this.client,
    required this.callerId,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [

            const Text('Incoming call', style: TextStyle(fontSize: 18)),
            const SizedBox(height: 8),
            Text(callerId, style: const TextStyle(fontSize: 22)),
            const SizedBox(height: 48),

            ElevatedButton(
              onPressed: () => client.answer(),
              child: const Text('Accept'),
            ),
            const SizedBox(height: 16),

            ElevatedButton(
              onPressed: () => client.reject(),
              child: const Text('Reject'),
            ),

          ],
        ),
      ),
    );
  }
}
