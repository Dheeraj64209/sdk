import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/sdk_constants.dart';
import '../events/connection_event.dart';
import '../events/error_event.dart';
import '../state/connection_state.dart';
import '../state/registration_state.dart';
import '../state/transport_state.dart';
import '../utils/logger.dart';
import '../utils/stream_extensions.dart';
import 'socket_message_parser.dart';
import 'socket_protocol.dart';

class SocketService {
  SocketService({
    required this.socketUrl,
    required this.autoReconnect,
    Logger? logger,
  })  : _logger = logger ?? Logger(),
        _parser = SocketMessageParser();

  final String socketUrl;
  final bool autoReconnect;
  final Logger _logger;
  final SocketMessageParser _parser;

  final StreamController<SocketEnvelope> _messages =
      StreamController<SocketEnvelope>.broadcast();
  final StreamController<ConnectionEvent> _connectionEvents =
      StreamController<ConnectionEvent>.broadcast();
  final StreamController<ErrorEvent> _errorEvents =
      StreamController<ErrorEvent>.broadcast();

  WebSocket? _socket;
  StreamSubscription<dynamic>? _socketSubscription;
  TransportState _transportState = TransportState.idle;
  int _reconnectAttempts = 0;
  bool _manualClose = false;

  Stream<SocketEnvelope> get messages => _messages.stream;
  Stream<ConnectionEvent> get connectionEvents => _connectionEvents.stream;
  Stream<ErrorEvent> get errorEvents => _errorEvents.stream;
  TransportState get transportState => _transportState;

  Future<void> connect() async {
    _manualClose = false;
    _transportState = TransportState.opening;
    _connectionEvents.addIfOpen(ConnectionEvent(
      connectionState: ConnectionStateStatus.connecting,
      registrationState: RegistrationState.unregistered,
      message: 'Opening socket',
    ));

    try {
      _socket = await WebSocket.connect(
        socketUrl,
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw TimeoutException(
          'Timed out while connecting to $socketUrl',
        ),
      );
      _transportState = TransportState.open;
      _reconnectAttempts = 0;
      _socketSubscription = _socket!.listen(
        _handleMessage,
        onDone: _handleDone,
        onError: _handleError,
        cancelOnError: true,
      );
      _connectionEvents.addIfOpen(ConnectionEvent(
        connectionState: ConnectionStateStatus.connected,
        registrationState: RegistrationState.unregistered,
        message: 'Socket connected',
      ));
    } catch (error) {
      _handleError(error);
      rethrow;
    }
  }

  Future<void> send(SocketEnvelope envelope) async {
    final WebSocket? socket = _socket;
    if (socket == null || socket.readyState != WebSocket.open) {
      throw StateError('Socket is not connected');
    }
    socket.add(jsonEncode(envelope.toJson()));
  }

  Future<void> close() async {
    _manualClose = true;
    _transportState = TransportState.closing;
    await _socketSubscription?.cancel();
    await _socket?.close();
    _socketSubscription = null;
    _socket = null;
    _transportState = TransportState.closed;
  }

  void _handleMessage(dynamic raw) {
    _messages.addIfOpen(_parser.parse(raw));
  }

  void _handleDone() {
    _socketSubscription = null;
    _socket = null;
    _transportState = TransportState.closed;
    if (!_manualClose && autoReconnect) {
      _scheduleReconnect();
      return;
    }
    _connectionEvents.addIfOpen(ConnectionEvent(
      connectionState: ConnectionStateStatus.disconnected,
      registrationState: RegistrationState.unregistered,
      message: 'Socket closed',
    ));
  }

  void _handleError(Object error) {
    _logger.error('Socket error: $error');
    _transportState = TransportState.error;
    _errorEvents.addIfOpen(ErrorEvent(
      code: 'socket_error',
      message: 'Socket transport failed: $error',
      cause: error,
    ));
    if (!_manualClose && autoReconnect) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_reconnectAttempts >= SdkConstants.maxReconnectAttempts) {
      _connectionEvents.addIfOpen(ConnectionEvent(
        connectionState: ConnectionStateStatus.failed,
        registrationState: RegistrationState.failed,
        message: 'Max reconnect attempts reached',
      ));
      return;
    }

    _reconnectAttempts += 1;
    final int delayMs = SdkConstants.reconnectBaseDelayMs * _reconnectAttempts;
    _connectionEvents.addIfOpen(ConnectionEvent(
      connectionState: ConnectionStateStatus.reconnecting,
      registrationState: RegistrationState.unregistered,
      message: 'Reconnecting in ${delayMs}ms',
    ));

    Future<void>.delayed(Duration(milliseconds: delayMs), () async {
      if (_manualClose) {
        return;
      }
      try {
        await connect();
      } catch (_) {
        // retry loop continues through error handler
      }
    });
  }
}
