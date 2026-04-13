import 'package:flutter/widgets.dart';

class LifecycleService with WidgetsBindingObserver {
  final ValueNotifier<AppLifecycleState> lifecycleState =
      ValueNotifier<AppLifecycleState>(AppLifecycleState.resumed);

  void attach() {
    WidgetsBinding.instance.addObserver(this);
  }

  void detach() {
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    lifecycleState.value = state;
  }
}
