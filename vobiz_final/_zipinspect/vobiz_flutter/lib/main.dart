import 'package:flutter/material.dart';
import 'client/vobiz_client.dart';
import 'screens/login_screen.dart';
import 'screens/dialer_screen.dart';
import 'screens/incoming_screen.dart';
import 'screens/incall_screen.dart';

void main() => runApp(const VobizApp());

class VobizApp extends StatefulWidget {
  const VobizApp({super.key});

  @override
  State<VobizApp> createState() => _VobizAppState();
}

class _VobizAppState extends State<VobizApp> {
  static const _wsUrl = String.fromEnvironment(
    'VOBIZ_WS_URL',
    defaultValue: 'wss://registrar.vobiz.ai:5063/',
  );
  static const _sipServer = String.fromEnvironment(
    'VOBIZ_SIP_SERVER',
    defaultValue: 'registrar.vobiz.ai',
  );

  final client = VobizClient(
    wsUrl: _wsUrl,
    sipServer: _sipServer,
  );

  @override
  void dispose() {
    client.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Vobiz',
      home: StreamBuilder<VobizState>(
        stream: client.stream,
        initialData: client.state,
        builder: (context, snapshot) {
          return _resolveScreen(snapshot.data!);
        },
      ),
    );
  }

  Widget _resolveScreen(VobizState state) {
    if (state.call == CallState.incoming) {
      return IncomingScreen(
        client: client,
        callerId: state.callerId ?? 'Unknown',
      );
    }

    if (state.call == CallState.inCall ||
        state.call == CallState.calling ||
        state.call == CallState.ringing) {
      return InCallScreen(client: client);
    }

    if (state.registration == RegistrationState.registered) {
      return DialerScreen(client: client);
    }

    return LoginScreen(client: client);
  }
}
