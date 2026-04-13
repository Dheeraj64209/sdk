import 'package:flutter/material.dart';

/// Reusable controls shown on the active call screen.
class CallControls extends StatelessWidget {
  const CallControls({
    super.key,
    required this.isMuted,
    this.onToggleMute,
    this.onHangup,
  });

  final bool isMuted;
  final VoidCallback? onToggleMute;
  final VoidCallback? onHangup;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        _ControlButton(
          icon: isMuted ? Icons.mic_off : Icons.mic,
          label: isMuted ? 'Unmute' : 'Mute',
          onPressed: onToggleMute,
          backgroundColor: const Color(0xFFE9EEF5),
          foregroundColor: Colors.black87,
        ),
        const SizedBox(width: 16),
        _ControlButton(
          icon: Icons.call_end,
          label: 'Hangup',
          onPressed: onHangup,
          backgroundColor: const Color(0xFFD92D20),
          foregroundColor: Colors.white,
        ),
      ],
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final Color backgroundColor;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SizedBox(
          width: 72,
          height: 72,
          child: FilledButton(
            onPressed: onPressed,
            style: FilledButton.styleFrom(
              backgroundColor: backgroundColor,
              foregroundColor: foregroundColor,
              shape: const CircleBorder(),
            ),
            child: Icon(icon, size: 28),
          ),
        ),
        const SizedBox(height: 8),
        Text(label),
      ],
    );
  }
}
