// lib/screens/login_screen.dart
// Connect screen — username, password, connect button.

import 'package:flutter/material.dart';
import '../client/vobiz_client.dart';

class LoginScreen extends StatefulWidget {
  final VobizClient client;
  const LoginScreen({super.key, required this.client});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _onConnect() {
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();
    if (username.isEmpty || password.isEmpty) return;
    widget.client.connect(username, password);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<VobizState>(
      stream: widget.client.stream,
      initialData: widget.client.state,
      builder: (context, snapshot) {
        final state    = snapshot.data!;
        final busy     = state.connection    == ClientConnectionState.connecting ||
                         state.registration  == RegistrationState.registering;
        final hasError = state.errorMessage  != null;

        return Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [

                const Text('Vobiz', style: TextStyle(fontSize: 24)),
                const SizedBox(height: 32),

                TextField(
                  controller: _usernameController,
                  decoration: const InputDecoration(labelText: 'Username'),
                  keyboardType: TextInputType.emailAddress,
                  enabled: !busy,
                ),
                const SizedBox(height: 16),

                TextField(
                  controller: _passwordController,
                  decoration: const InputDecoration(labelText: 'Password'),
                  obscureText: true,
                  enabled: !busy,
                ),
                const SizedBox(height: 24),

                Text(_statusText(state)),
                const SizedBox(height: 8),

                if (hasError)
                  Text(
                    state.errorMessage!,
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                const SizedBox(height: 16),

                busy
                    ? const CircularProgressIndicator()
                    : ElevatedButton(
                        onPressed: _onConnect,
                        child: const Text('Connect'),
                      ),

              ],
            ),
          ),
        );
      },
    );
  }

  String _statusText(VobizState state) {
    switch (state.connection) {
      case ClientConnectionState.connecting:
        return 'Connecting...';
      case ClientConnectionState.connected:
        switch (state.registration) {
          case RegistrationState.registering: return 'Registering...';
          case RegistrationState.failed:      return 'Registration failed';
          default:                            return 'Connected';
        }
      default:
        return 'Disconnected';
    }
  }
}
