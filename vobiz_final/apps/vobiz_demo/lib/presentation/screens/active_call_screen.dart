import 'package:flutter/material.dart';

import '../widgets/call_controls.dart';

/// Dedicated in-call screen shown while a call is ringing or active.
class ActiveCallScreen extends StatelessWidget {
  const ActiveCallScreen({
    super.key,
    required this.remoteIdentity,
    required this.callState,
    required this.isMuted,
    required this.onToggleMute,
    required this.onHangup,
  });

  final String remoteIdentity;
  final String callState;
  final bool isMuted;
  final VoidCallback onToggleMute;
  final VoidCallback onHangup;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1728),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: const Text('Call'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: <Widget>[
              const Spacer(),
              CircleAvatar(
                radius: 48,
                backgroundColor: const Color(0xFF1E293B),
                child: Text(
                  remoteIdentity.isEmpty
                      ? '?'
                      : remoteIdentity[0].toUpperCase(),
                  style: const TextStyle(
                    fontSize: 32,
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                remoteIdentity.isEmpty ? 'Unknown caller' : remoteIdentity,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                callState,
                style: const TextStyle(
                  fontSize: 16,
                  color: Color(0xFFB6C2D2),
                ),
              ),
              const Spacer(),
              CallControls(
                isMuted: isMuted,
                onToggleMute: onToggleMute,
                onHangup: onHangup,
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}
