import 'dart:async';
import 'dart:convert';

import 'package:notalone/core/result/result.dart';
import 'package:notalone/features/session/data/dart_io_lan_server.dart';
import 'package:notalone/features/session/domain/lan_client.dart';
import 'package:notalone/features/session/domain/qr_session_payload.dart';
import 'package:notalone/features/session/domain/session_failure.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Client WebSocket du spike MVP-03 (`web_socket_channel`). Un timeout de
/// connexion est interprété comme un WiFi qui isole les clients (R7) ;
/// un refus (403 : mauvais token) comme une erreur franche.
class WebSocketLanClient implements LanClient {
  WebSocketLanClient({this.connectTimeout = const Duration(seconds: 5)});

  final Duration connectTimeout;
  static const Duration _pongTimeout = Duration(seconds: 3);

  WebSocketChannel? _channel;
  final StreamController<String> _messages = StreamController.broadcast();
  final StreamController<void> _disconnections = StreamController.broadcast();
  final Map<int, Completer<void>> _pendingPings = {};
  int _nextNonce = 0;

  @override
  Stream<String> get messages => _messages.stream;

  @override
  Stream<void> get disconnections => _disconnections.stream;

  @override
  Future<Result<void>> connect(QrSessionPayload payload) async {
    if (_channel != null) return const Result.ok(null);
    final uri = Uri(
      scheme: 'ws',
      host: payload.host,
      port: payload.port,
      path: DartIoLanServer.path,
      queryParameters: {'token': payload.token},
    );
    try {
      final channel = WebSocketChannel.connect(uri);
      await channel.ready.timeout(connectTimeout);
      _channel = channel;
      channel.stream.listen(
        _handleFrame,
        onDone: _handleClosed,
        onError: (_) => _handleClosed(),
        cancelOnError: true,
      );
      return const Result.ok(null);
    } on TimeoutException {
      return const Result.err(ConnectionTimeoutFailure());
    } on Exception catch (exception) {
      return Result.err(ConnectionFailure('$exception'));
    }
  }

  @override
  void send(String text) {
    _channel?.sink.add(jsonEncode({'type': 'chat', 'text': text}));
  }

  @override
  Future<Result<Duration>> ping() async {
    final channel = _channel;
    if (channel == null) {
      return const Result.err(ConnectionFailure('non connecté'));
    }
    final nonce = _nextNonce++;
    final completer = Completer<void>();
    _pendingPings[nonce] = completer;
    final stopwatch = Stopwatch()..start();
    channel.sink.add(jsonEncode({'type': 'ping', 'nonce': nonce}));
    try {
      await completer.future.timeout(_pongTimeout);
      return Result.ok(stopwatch.elapsed);
    } on TimeoutException {
      return const Result.err(ConnectionFailure('pong non reçu'));
    } finally {
      _pendingPings.remove(nonce);
    }
  }

  @override
  Future<void> disconnect() async {
    final channel = _channel;
    _channel = null;
    await channel?.sink.close();
  }

  void _handleFrame(Object? data) {
    if (data is! String) return;
    final Object? decoded;
    try {
      decoded = jsonDecode(data);
    } on FormatException {
      return;
    }
    if (decoded is! Map<String, Object?>) return;
    switch (decoded['type']) {
      case 'pong':
        final nonce = decoded['nonce'];
        if (nonce is int) _pendingPings[nonce]?.complete();
      case 'chat':
        final text = decoded['text'];
        if (text is String) _messages.add(text);
      default:
        return; // Type inconnu : toléré (ascendant), ignoré.
    }
  }

  void _handleClosed() {
    if (_channel == null) return;
    _channel = null;
    _disconnections.add(null);
  }
}
