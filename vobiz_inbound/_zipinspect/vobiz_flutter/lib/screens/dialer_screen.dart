// lib/screens/dialer_screen.dart
// Dialer screen — phone number input + call button.

import 'package:flutter/material.dart';
import '../client/vobiz_client.dart';

class DialerScreen extends StatefulWidget {
  final VobizClient client;
  const DialerScreen({super.key, required this.client});

  @override
  State<DialerScreen> createState() => _DialerScreenState();
}

class _DialerScreenState extends State<DialerScreen> {
  final _numberController = TextEditingController();

  @override
  void dispose() {
    _numberController.dispose();
    super.dispose();
  }

  Future<void> _onCall() async {
    final number = _numberController.text.trim();

    if (number.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Enter phone number")),
      );
      return;
    }

    widget.client.call(number);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<VobizState>(
      stream: widget.client.stream,
      initialData: widget.client.state,
      builder: (context, snapshot) {
        final state = snapshot.data!;
        final idle = state.call == CallState.idle;
        final hasError = state.errorMessage != null;

        return Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('Registered', style: TextStyle(color: Colors.green)),
                const SizedBox(height: 32),
                TextField(
                  controller: _numberController,
                  decoration: const InputDecoration(labelText: 'Phone number'),
                  keyboardType: TextInputType.phone,
                  enabled: idle,
                ),
                const SizedBox(height: 24),
                if (hasError)
                  Text(
                    state.errorMessage!,
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: idle ? _onCall : null,
                  child: const Text('Call'),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => widget.client.disconnect(),
                  child: const Text('Disconnect'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
