// lib/services/sip_service.dart
//
// Minimal SIP-over-WebSocket service for the Vobiz mobile client.
// Handles: REGISTER, INVITE (outbound + inbound), provisional responses,
// 200 OK, ACK, BYE, and digest-auth challenges.

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../utils/logger.dart';

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

enum SipConnectionState { disconnected, connecting, connected }

enum SipRegistrationState { unregistered, registering, registered, failed }

// ---------------------------------------------------------------------------
// SIP Message Model
// ---------------------------------------------------------------------------

class SipMessage {
  final String firstLine;
  final Map<String, String> headers;
  final String body;

  const SipMessage({
    required this.firstLine,
    required this.headers,
    required this.body,
  });

  bool get isRequest => !firstLine.startsWith('SIP/');
  String get method => firstLine.split(' ').first;
  int get statusCode => int.tryParse(firstLine.split(' ')[1]) ?? 0;

  String? header(String name) {
    final key = name.toLowerCase();
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == key) {
        return entry.value;
      }
    }
    return null;
  }
}

// ---------------------------------------------------------------------------
// SIP Parser
// ---------------------------------------------------------------------------

class SipParser {
  static SipMessage parse(String raw) {
    final parts = raw.split(RegExp(r'\r?\n\r?\n', multiLine: true));
    final headerSection = parts[0];
    final body = parts.length > 1 ? parts.sublist(1).join('\n\n') : '';
    final lines = headerSection.split(RegExp(r'\r?\n'));
    final firstLine = lines[0].trim();
    final headers = <String, String>{};

    for (int i = 1; i < lines.length; i++) {
      final colon = lines[i].indexOf(':');
      if (colon == -1) {
        continue;
      }
      headers[lines[i].substring(0, colon).trim()] =
          lines[i].substring(colon + 1).trim();
    }

    return SipMessage(
      firstLine: firstLine,
      headers: headers,
      body: body.trim(),
    );
  }
}

// ---------------------------------------------------------------------------
// SIP Message Builder
// ---------------------------------------------------------------------------

class SipBuilder {
  static String register({
    required String sipServer,
    required String username,
    required String localTag,
    required String callId,
    required int cseq,
    String? authHeader,
  }) {
    final from = 'sip:$username@$sipServer';
    final contact = '<sip:$username@vobiz-client>';
    final buf = StringBuffer()
      ..writeln('Via: SIP/2.0/WSS vobiz-client;branch=z9hG4bK${_branch()}')
      ..writeln('From: <$from>;tag=$localTag')
      ..writeln('To: <$from>')
      ..writeln('Call-ID: $callId')
      ..writeln('CSeq: $cseq REGISTER')
      ..writeln('Contact: $contact')
      ..writeln('Max-Forwards: 70')
      ..writeln('Expires: 3600')
      ..writeln('Content-Length: 0');
    if (authHeader != null) {
      buf.writeln('Authorization: $authHeader');
    }
    return 'REGISTER sip:$sipServer SIP/2.0\r\n${buf.toString().trim()}\r\n\r\n';
  }

  static String invite({
    required String sipServer,
    required String fromUser,
    required String toUser,
    required String localTag,
    required String callId,
    required int cseq,
    required String sdp,
    String? authHeaderName,
    String? authHeader,
  }) {
    final contentLength = utf8.encode(sdp).length;
    final lines = <String>[
      'INVITE sip:$toUser@$sipServer SIP/2.0',
      'Via: SIP/2.0/WSS vobiz-client;branch=z9hG4bK${_branch()}',
      'From: <sip:$fromUser@$sipServer>;tag=$localTag',
      'To: <sip:$toUser@$sipServer>',
      'Call-ID: $callId',
      'CSeq: $cseq INVITE',
      'Contact: <sip:$fromUser@vobiz-client>',
      'Max-Forwards: 70',
      'Allow: INVITE, ACK, CANCEL, BYE, OPTIONS',
      'Supported: timer',
      'User-Agent: vobiz_mobile_flutter',
    ];
    if (authHeaderName != null && authHeader != null) {
      lines.add('$authHeaderName: $authHeader');
    }
    lines.addAll(<String>[
      'Content-Type: application/sdp',
      'Content-Length: $contentLength',
      '',
      sdp,
    ]);
    return lines.join('\r\n');
  }

  static String ok200({
    required SipMessage invite,
    required String fromUser,
    required String localTag,
    required String sdp,
  }) {
    final contentLength = utf8.encode(sdp).length;
    final inviteTo = invite.header('To') ?? '';
    final taggedTo =
        inviteTo.contains('tag=') ? inviteTo : '$inviteTo;tag=$localTag';
    return <String>[
      'SIP/2.0 200 OK',
      'Via: ${invite.header('Via') ?? ''}',
      'From: ${invite.header('From') ?? ''}',
      'To: $taggedTo',
      'Call-ID: ${invite.header('Call-ID') ?? ''}',
      'CSeq: ${invite.header('CSeq') ?? ''}',
      'Contact: <sip:$fromUser@vobiz-client>',
      'Content-Type: application/sdp',
      'Content-Length: $contentLength',
      '',
      sdp,
    ].join('\r\n');
  }

  static String ringing({
    required SipMessage invite,
    required String localTag,
  }) {
    final inviteTo = invite.header('To') ?? '';
    final taggedTo =
        inviteTo.contains('tag=') ? inviteTo : '$inviteTo;tag=$localTag';
    return <String>[
      'SIP/2.0 180 Ringing',
      'Via: ${invite.header('Via') ?? ''}',
      'From: ${invite.header('From') ?? ''}',
      'To: $taggedTo',
      'Call-ID: ${invite.header('Call-ID') ?? ''}',
      'CSeq: ${invite.header('CSeq') ?? ''}',
      'Content-Length: 0',
      '',
      '',
    ].join('\r\n');
  }

  static String ack({
    required String requestUri,
    required String fromUser,
    required String toHeader,
    required String sipServer,
    required String localTag,
    required String callId,
    required int cseq,
  }) {
    return <String>[
      'ACK $requestUri SIP/2.0',
      'Via: SIP/2.0/WSS vobiz-client;branch=z9hG4bK${_branch()}',
      'From: <sip:$fromUser@$sipServer>;tag=$localTag',
      'To: $toHeader',
      'Call-ID: $callId',
      'CSeq: $cseq ACK',
      'Max-Forwards: 70',
      'Content-Length: 0',
      '',
      '',
    ].join('\r\n');
  }

  static String bye({
    required String requestUri,
    required String fromUser,
    required String toHeader,
    required String sipServer,
    required String localTag,
    required String callId,
    required int cseq,
  }) {
    return <String>[
      'BYE $requestUri SIP/2.0',
      'Via: SIP/2.0/WSS vobiz-client;branch=z9hG4bK${_branch()}',
      'From: <sip:$fromUser@$sipServer>;tag=$localTag',
      'To: $toHeader',
      'Call-ID: $callId',
      'CSeq: $cseq BYE',
      'Max-Forwards: 70',
      'Content-Length: 0',
      '',
      '',
    ].join('\r\n');
  }

  static String busyHere({
    required SipMessage invite,
    required String localTag,
  }) {
    final inviteTo = invite.header('To') ?? '';
    final taggedTo =
        inviteTo.contains('tag=') ? inviteTo : '$inviteTo;tag=$localTag';
    return <String>[
      'SIP/2.0 486 Busy Here',
      'Via: ${invite.header('Via') ?? ''}',
      'From: ${invite.header('From') ?? ''}',
      'To: $taggedTo',
      'Call-ID: ${invite.header('Call-ID') ?? ''}',
      'CSeq: ${invite.header('CSeq') ?? ''}',
      'Content-Length: 0',
      '',
      '',
    ].join('\r\n');
  }

  static String _branch() =>
      Random().nextInt(0x7fffffff).toRadixString(16).padLeft(8, '0');
}

// ---------------------------------------------------------------------------
// SIP Digest Auth Helper
// ---------------------------------------------------------------------------

class SipDigestAuth {
  static String? buildAuthHeader({
    required String wwwAuthenticate,
    required String method,
    required String uri,
    required String username,
    required String password,
  }) {
    final realm = _extract(wwwAuthenticate, 'realm');
    final nonce = _extract(wwwAuthenticate, 'nonce');
    if (realm == null || nonce == null) {
      return null;
    }

    final ha1 = _md5('$username:$realm:$password');
    final ha2 = _md5('$method:$uri');
    final response = _md5('$ha1:$nonce:$ha2');
    return 'Digest username="$username", realm="$realm", '
        'nonce="$nonce", uri="$uri", response="$response"';
  }

  static String _md5(String input) =>
      md5.convert(utf8.encode(input)).toString();

  static String? _extract(String header, String key) =>
      RegExp('$key="([^"]+)"').firstMatch(header)?.group(1);
}

// ---------------------------------------------------------------------------
// SIPService
// ---------------------------------------------------------------------------

class SIPService {
  final String wsUrl;
  final String sipServer;

  String? _username;
  String? _password;

  late final String _localTag;
  late final String _registerCallId;
  int _cseq = 1;
  bool _manualDisconnect = false;

  String? _activeCallId;
  String? _activeRemoteTag;
  String? _activeToUser;
  String? _activeRemoteTarget;
  String? _activeRemotePartyHeader;
  String? _activeInviteSdp;
  int? _activeInviteCSeq;
  SipMessage? _pendingInvite;

  WebSocketChannel? _socket;
  Timer? _registrationRefreshTimer;
  Timer? _optionsKeepAliveTimer;

  final _connectionState = ValueNotifier(SipConnectionState.disconnected);
  final _registrationState = ValueNotifier(SipRegistrationState.unregistered);

  ValueNotifier<SipConnectionState> get connectionState => _connectionState;
  ValueNotifier<SipRegistrationState> get registrationState =>
      _registrationState;

  // Callbacks
  void Function()? onRegistered;
  void Function(String reason)? onRegistrationFailed;
  void Function()? onRemoteRinging;
  void Function(String? sdp)? onCallProgress;
  void Function(String callerId, String sdp)? onIncomingCall;
  void Function(String sdp)? onCallAnswered;
  void Function()? onCallEnded;
  void Function(String reason)? onCallFailed;
  void Function(String reason)? onSocketError;

  SIPService({required this.wsUrl, required this.sipServer}) {
    _localTag = _rand(8);
    _registerCallId = '${_rand(12)}@vobiz-client';
  }

  Future<void> connect() async {
    _manualDisconnect = false;
    _connectionState.value = SipConnectionState.connecting;
    try {
      _socket = IOWebSocketChannel.connect(
        Uri.parse(wsUrl),
        protocols: const <String>['sip'],
        pingInterval: const Duration(seconds: 30),
        connectTimeout: const Duration(seconds: 10),
      );
      _connectionState.value = SipConnectionState.connected;
      Log.info('SIP', 'WebSocket connected to $wsUrl');
      _listenToSocket();
    } catch (e) {
      _connectionState.value = SipConnectionState.disconnected;
      Log.error('SIP', 'WebSocket connection failed: $e');
      onSocketError?.call('SIP socket connection failed: $e');
      rethrow;
    }
  }

  void register(String username, String password) {
    _username = username;
    _password = password;
    _registrationState.value = SipRegistrationState.registering;
    _send(
      SipBuilder.register(
        sipServer: sipServer,
        username: username,
        localTag: _localTag,
        callId: _registerCallId,
        cseq: _cseq++,
      ),
    );
  }

  void call(String toUser, String sdp) {
    _activeCallId = '${_rand(12)}@vobiz-client';
    _activeToUser = toUser;
    _activeInviteSdp = sdp;
    _activeRemoteTarget = 'sip:$toUser@$sipServer';
    _activeRemotePartyHeader = '<sip:$toUser@$sipServer>';
    _sendInvite();
  }

  void answer(String sdp) {
    if (_pendingInvite == null) {
      return;
    }
    _send(
      SipBuilder.ok200(
        invite: _pendingInvite!,
        fromUser: _username!,
        localTag: _localTag,
        sdp: sdp,
      ),
    );
    _pendingInvite = null;
  }

  void reject() {
    if (_pendingInvite == null) {
      return;
    }
    _send(SipBuilder.busyHere(invite: _pendingInvite!, localTag: _localTag));
    _pendingInvite = null;
  }

  void hangup() {
    if (_activeCallId == null || _username == null) {
      return;
    }
    _send(
      SipBuilder.bye(
        requestUri: _activeRemoteTarget ?? 'sip:${_activeToUser!}@$sipServer',
        fromUser: _username!,
        toHeader: _activeRemotePartyHeader ?? _buildFallbackToHeader(),
        sipServer: sipServer,
        localTag: _localTag,
        callId: _activeCallId!,
        cseq: _cseq++,
      ),
    );
    _clearCallState();
    onCallEnded?.call();
  }

  void disconnect() {
    _manualDisconnect = true;
    _registrationRefreshTimer?.cancel();
    _optionsKeepAliveTimer?.cancel();
    _clearCallState();
    _socket?.sink.close();
    _connectionState.value = SipConnectionState.disconnected;
    _registrationState.value = SipRegistrationState.unregistered;
  }

  void _sendInvite({
    String? authHeaderName,
    String? authHeader,
  }) {
    if (_activeCallId == null ||
        _activeToUser == null ||
        _activeInviteSdp == null ||
        _username == null) {
      return;
    }

    _activeInviteCSeq = _cseq;
    _send(
      SipBuilder.invite(
        sipServer: sipServer,
        fromUser: _username!,
        toUser: _activeToUser!,
        localTag: _localTag,
        callId: _activeCallId!,
        cseq: _cseq++,
        sdp: _activeInviteSdp!,
        authHeaderName: authHeaderName,
        authHeader: authHeader,
      ),
    );
  }

  void _listenToSocket() {
    _socket!.stream.listen(
      (raw) => _handleMessage(raw.toString()),
      onError: (e) {
        Log.error('SIP', 'WebSocket error: $e');
        _connectionState.value = SipConnectionState.disconnected;
        _registrationState.value = SipRegistrationState.failed;
        _registrationRefreshTimer?.cancel();
        _optionsKeepAliveTimer?.cancel();
        if (!_manualDisconnect) {
          onSocketError?.call('SIP socket error: $e');
        }
      },
      onDone: () {
        Log.warn('SIP', 'WebSocket closed');
        _connectionState.value = SipConnectionState.disconnected;
        _registrationRefreshTimer?.cancel();
        _optionsKeepAliveTimer?.cancel();
        if (!_manualDisconnect) {
          _registrationState.value = SipRegistrationState.failed;
          onSocketError?.call('SIP socket closed');
        }
      },
    );
  }

  void _handleMessage(String raw) {
    if (raw.trim().isEmpty) {
      return;
    }
    Log.info('SIP <<', _summarizeSip(raw));
    final msg = SipParser.parse(raw);
    if (msg.isRequest) {
      _handleRequest(msg);
    } else {
      _handleResponse(msg);
    }
  }

  void _handleRequest(SipMessage msg) {
    switch (msg.method) {
      case 'INVITE':
        _handleIncomingInvite(msg);
        break;
      case 'OPTIONS':
        _handleIncomingOptions(msg);
        break;
      case 'CANCEL':
        _handleIncomingCancel(msg);
        break;
      case 'ACK':
        break;
      case 'BYE':
        _handleIncomingBye(msg);
        break;
      default:
        break;
    }
  }

  void _handleIncomingInvite(SipMessage msg) {
    _pendingInvite = msg;
    _activeCallId = msg.header('Call-ID');
    final from = msg.header('From') ?? '';
    final callerId =
        RegExp(r'sip:([^@>]+)').firstMatch(from)?.group(1) ?? 'Unknown';
    _activeToUser = callerId;
    _activeRemoteTag = _extractTag(from);
    _activeRemoteTarget = _extractUri(msg.header('Contact') ?? from);
    _activeRemotePartyHeader = from;
    _send(SipBuilder.ringing(invite: msg, localTag: _localTag));
    Log.info('SIP', 'Incoming call from $callerId');
    onIncomingCall?.call(callerId, msg.body);
  }

  void _handleIncomingBye(SipMessage msg) {
    _send(
      <String>[
        'SIP/2.0 200 OK',
        'Via: ${msg.header('Via') ?? ''}',
        'From: ${msg.header('From') ?? ''}',
        'To: ${msg.header('To') ?? ''}',
        'Call-ID: ${msg.header('Call-ID') ?? ''}',
        'CSeq: ${msg.header('CSeq') ?? ''}',
        'Content-Length: 0',
        '',
        '',
      ].join('\r\n'),
    );
    _clearCallState();
    onCallEnded?.call();
  }

  void _handleIncomingOptions(SipMessage msg) {
    _send(
      <String>[
        'SIP/2.0 200 OK',
        'Via: ${msg.header('Via') ?? ''}',
        'From: ${msg.header('From') ?? ''}',
        'To: ${msg.header('To') ?? ''}',
        'Call-ID: ${msg.header('Call-ID') ?? ''}',
        'CSeq: ${msg.header('CSeq') ?? ''}',
        'Content-Length: 0',
        '',
        '',
      ].join('\r\n'),
    );
  }

  void _handleIncomingCancel(SipMessage msg) {
    _send(
      <String>[
        'SIP/2.0 200 OK',
        'Via: ${msg.header('Via') ?? ''}',
        'From: ${msg.header('From') ?? ''}',
        'To: ${msg.header('To') ?? ''}',
        'Call-ID: ${msg.header('Call-ID') ?? ''}',
        'CSeq: ${msg.header('CSeq') ?? ''}',
        'Content-Length: 0',
        '',
        '',
      ].join('\r\n'),
    );
    _clearCallState();
    onCallEnded?.call();
  }

  void _handleResponse(SipMessage msg) {
    final cseq = msg.header('CSeq') ?? '';
    if (cseq.contains('REGISTER')) {
      _handleRegisterResponse(msg);
    } else if (cseq.contains('INVITE')) {
      _handleInviteResponse(msg);
    }
  }

  void _handleRegisterResponse(SipMessage msg) {
    switch (msg.statusCode) {
      case 200:
        Log.info('SIP', 'Registered successfully');
        _registrationState.value = SipRegistrationState.registered;
        _startRegistrationRefresh();
        _startOptionsKeepAlive();
        onRegistered?.call();
        break;
      case 401:
      case 407:
        Log.info('SIP', 'Auth challenge - retrying with digest');
        final challenge = msg.header('WWW-Authenticate') ??
            msg.header('Proxy-Authenticate') ??
            '';
        final auth = SipDigestAuth.buildAuthHeader(
          wwwAuthenticate: challenge,
          method: 'REGISTER',
          uri: 'sip:$sipServer',
          username: _username!,
          password: _password!,
        );
        if (auth == null) {
          Log.error('SIP', 'Failed to parse auth challenge');
          _registrationState.value = SipRegistrationState.failed;
          onRegistrationFailed?.call('Could not parse auth challenge');
          return;
        }
        _send(
          SipBuilder.register(
            sipServer: sipServer,
            username: _username!,
            localTag: _localTag,
            callId: _registerCallId,
            cseq: _cseq++,
            authHeader: auth,
          ),
        );
        break;
      case 403:
        Log.error('SIP', 'Registration forbidden (403) - wrong credentials');
        _registrationState.value = SipRegistrationState.failed;
        onRegistrationFailed?.call('Wrong credentials (403 Forbidden)');
        break;
      case 404:
        Log.error('SIP', 'User not found (404)');
        _registrationState.value = SipRegistrationState.failed;
        onRegistrationFailed?.call('User not found (404)');
        break;
      default:
        Log.warn('SIP', 'Unhandled REGISTER response: ${msg.statusCode}');
    }
  }

  void _handleInviteResponse(SipMessage msg) {
    switch (msg.statusCode) {
      case 100:
        Log.info('SIP', 'Call trying');
        break;
      case 180:
        Log.info('SIP', 'Remote ringing');
        _updateActiveDialogFromResponse(msg);
        onRemoteRinging?.call();
        break;
      case 183:
        Log.info('SIP', 'Session progress');
        _updateActiveDialogFromResponse(msg);
        onCallProgress?.call(msg.body.isEmpty ? null : msg.body);
        break;
      case 200:
        Log.info('SIP', 'Call answered');
        _updateActiveDialogFromResponse(msg);
        _send(
          SipBuilder.ack(
            requestUri:
                _activeRemoteTarget ?? 'sip:${_activeToUser!}@$sipServer',
            fromUser: _username!,
            toHeader: _activeRemotePartyHeader ?? _buildFallbackToHeader(),
            sipServer: sipServer,
            localTag: _localTag,
            callId: _activeCallId!,
            cseq: _activeInviteCSeq ?? _extractCSeqNumber(msg.header('CSeq')),
          ),
        );
        onCallAnswered?.call(msg.body);
        break;
      case 401:
      case 407:
        _handleInviteAuthChallenge(msg);
        break;
      case 486:
        Log.warn('SIP', 'Remote busy (486)');
        _clearCallState();
        onCallFailed?.call('Remote party is busy');
        break;
      case 603:
        Log.warn('SIP', 'Call declined (603)');
        _clearCallState();
        onCallFailed?.call('Remote party declined the call');
        break;
      default:
        if (msg.statusCode >= 300) {
          final reason = _reasonPhrase(msg);
          Log.warn('SIP', 'Call failed: ${msg.statusCode} $reason');
          _clearCallState();
          onCallFailed?.call('Call failed (${msg.statusCode} $reason)');
          return;
        }
        Log.warn('SIP', 'Unhandled INVITE response: ${msg.statusCode}');
    }
  }

  void _handleInviteAuthChallenge(SipMessage msg) {
    final challenge = msg.header('Proxy-Authenticate') ??
        msg.header('WWW-Authenticate') ??
        '';
    if (challenge.isEmpty ||
        _username == null ||
        _password == null ||
        _activeToUser == null ||
        _activeInviteSdp == null) {
      _clearCallState();
      onCallFailed?.call('Call authentication failed');
      return;
    }

    final auth = SipDigestAuth.buildAuthHeader(
      wwwAuthenticate: challenge,
      method: 'INVITE',
      uri: 'sip:${_activeToUser!}@$sipServer',
      username: _username!,
      password: _password!,
    );
    if (auth == null) {
      _clearCallState();
      onCallFailed?.call('Could not parse call authentication challenge');
      return;
    }

    Log.info('SIP', 'INVITE auth challenge - retrying with digest');
    _sendInvite(
      authHeaderName:
          msg.statusCode == 407 ? 'Proxy-Authorization' : 'Authorization',
      authHeader: auth,
    );
  }

  void _updateActiveDialogFromResponse(SipMessage msg) {
    _activeRemoteTag = _extractTag(msg.header('To') ?? '');
    _activeRemoteTarget = _extractUri(
      msg.header('Contact') ?? msg.header('To') ?? '',
    );
    _activeRemotePartyHeader = msg.header('To') ?? _activeRemotePartyHeader;
  }

  void _send(String message) {
    Log.info('SIP >>', _summarizeSip(message));
    _socket?.sink.add(message);
  }

  void _startRegistrationRefresh() {
    _registrationRefreshTimer?.cancel();
    _registrationRefreshTimer = Timer.periodic(
      const Duration(minutes: 55),
      (_) {
        if (_username == null || _password == null) {
          return;
        }
        Log.info('SIP', 'Refreshing SIP registration');
        register(_username!, _password!);
      },
    );
  }

  void _startOptionsKeepAlive() {
    _optionsKeepAliveTimer?.cancel();
    _optionsKeepAliveTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) {
        if (_username == null ||
            _connectionState.value != SipConnectionState.connected) {
          return;
        }
        final callId = '${_rand(12)}@vobiz-client';
        _send(
          <String>[
            'OPTIONS sip:admin@$sipServer SIP/2.0',
            'Via: SIP/2.0/WSS vobiz-client;branch=z9hG4bK${SipBuilder._branch()}',
            'From: <sip:${_username!}@$sipServer>;tag=$_localTag',
            'To: <sip:admin@$sipServer>',
            'Call-ID: $callId',
            'CSeq: ${_cseq++} OPTIONS',
            'Content-Length: 0',
            '',
            '',
          ].join('\r\n'),
        );
      },
    );
  }

  void _clearCallState() {
    _activeCallId = null;
    _activeRemoteTag = null;
    _activeToUser = null;
    _activeRemoteTarget = null;
    _activeRemotePartyHeader = null;
    _activeInviteSdp = null;
    _activeInviteCSeq = null;
    _pendingInvite = null;
  }

  int _extractCSeqNumber(String? header) =>
      int.tryParse((header ?? '').split(' ').first.trim()) ?? 1;

  String _extractTag(String header) =>
      RegExp(r'tag=([^;>\s]+)').firstMatch(header)?.group(1) ?? '';

  String? _extractUri(String header) =>
      RegExp(r'sip:[^>;]+').firstMatch(header)?.group(0);

  String _buildFallbackToHeader() {
    final toUser = _activeToUser;
    if (toUser == null) {
      return '<sip:unknown@$sipServer>';
    }
    if (_activeRemoteTag == null || _activeRemoteTag!.isEmpty) {
      return '<sip:$toUser@$sipServer>';
    }
    return '<sip:$toUser@$sipServer>;tag=$_activeRemoteTag';
  }

  String _reasonPhrase(SipMessage msg) {
    final parts = msg.firstLine.split(' ');
    return parts.length > 2 ? parts.sublist(2).join(' ') : 'Unknown error';
  }

  String _rand(int length) {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final rand = Random();
    return List<String>.generate(
      length,
      (_) => chars[rand.nextInt(chars.length)],
    ).join();
  }

  String _summarizeSip(String raw) {
    final normalized = raw.replaceAll('\r\n', '\n');
    final lines = normalized
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (lines.isEmpty) {
      return '<empty>';
    }

    final firstLine = lines.first;
    final interestingHeaders = <String>[];
    for (final prefix in const <String>[
      'Via:',
      'From:',
      'To:',
      'Call-ID:',
      'CSeq:',
      'WWW-Authenticate:',
      'Proxy-Authenticate:',
      'Contact:',
    ]) {
      final match = lines
          .where((line) => line.startsWith(prefix))
          .cast<String?>()
          .firstWhere((line) => line != null, orElse: () => null);
      if (match != null) {
        interestingHeaders.add(match);
      }
    }

    final bodySeparator = normalized.indexOf('\n\n');
    final hasBody = bodySeparator != -1 &&
        normalized.substring(bodySeparator + 2).trim().isNotEmpty;
    final suffix = hasBody ? ' [body]' : '';

    return (<String>[firstLine, ...interestingHeaders]).join(' | ') + suffix;
  }
}
