import 'package:flutter/material.dart';

import 'integration/dependency_injection.dart';
import 'presentation/screens/login_screen.dart';

class VobizDemoApp extends StatelessWidget {
  const VobizDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return DependencyInjection(
      child: MaterialApp(
        title: 'Vobiz Demo',
        theme: ThemeData.light(useMaterial3: true),
        home: const LoginScreen(),
      ),
    );
  }
}
