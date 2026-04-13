import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:vobiz_webrtc/vobiz_webrtc.dart';

import '../../integration/sdk_factory.dart';

/// View model responsible for SDK authentication and connection state.
class SdkViewModel extends ChangeNotifier {
  SdkViewModel({required SdkFactory factory})
    : _client = factory.createClient() {
    _connectionSub = _client.connectionEvents.listen((ConnectionEvent event) {
      connectionEvent = event;
      isBusy = false;
      notifyListeners();
    });

    _callSub = _client.callEvents.listen((CallEvent event) {
      latestCallEvent = event;
      notifyListeners();
    });

    _errorSub = _client.errorEvents.listen((ErrorEvent event) {
      latestError = event;
      isBusy = false;
      errorMessage = event.message;
      notifyListeners();
    });
  }

  final VobizClient _client;

  ConnectionEvent? connectionEvent;
  CallEvent? latestCallEvent;
  ErrorEvent? latestError;
  bool isBusy = false;
  String? errorMessage;

  StreamSubscription<ConnectionEvent>? _connectionSub;
  StreamSubscription<CallEvent>? _callSub;
  StreamSubscription<ErrorEvent>? _errorSub;

  VobizClient get client => _client;

  bool get isConnected => _client.isConnected;

  /// Performs SDK login with username and password.
  Future<bool> login(String username, String password) async {
    errorMessage = null;
    latestError = null;
    isBusy = true;
    notifyListeners();

    try {
      await _client.connect(
        CredentialConfig(username: username, password: password),
      );
      return true;
    } catch (error) {
      errorMessage = error.toString();
      return false;
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    errorMessage = null;
    await _client.disconnect();
    notifyListeners();
  }

  @override
  void dispose() {
    _connectionSub?.cancel();
    _callSub?.cancel();
    _errorSub?.cancel();
    super.dispose();
  }
}
