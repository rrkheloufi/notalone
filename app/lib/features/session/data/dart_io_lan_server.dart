import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:notalone/core/result/result.dart';
import 'package:notalone/features/session/data/local_ip.dart';
import 'package:notalone/features/session/domain/lan_server.dart';
import 'package:notalone/features/session/domain/session_failure.dart';

/// Serveur WebSocket `dart:io` du spike MVP-03. Protocole texte minimal en
/// attendant les DTOs versionnés de MVP-04 :
/// `{"type":"chat","text":…}` relayé à tous, `{"type":"ping","nonce":…}`
/// répondu par un `pong`. Le token (128 bits aléatoires) se vérifie en query
/// string à l'upgrade — le vrai `join_request` arrive en MVP-04/05.
class DartIoLanServer implements LanServer {
  static const String path = '/ws';

  final StreamController<LanServerEvent> _events =
      StreamController<LanServerEvent>.broadcast();
  final Map<int, WebSocket> _clients = {};
  HttpServer? _server;
  String? _token;
  int _nextClientId = 1;

  @override
  Stream<LanServerEvent> get events => _events.stream;

  @override
  Future<Result<LanServerInfo>> start() async {
    try {
      final host = await LocalIp.find();
      if (host == null) {
        return const Result.err(
          ServerStartFailure('aucune adresse IPv4 locale (WiFi coupé ?)'),
        );
      }
      final server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      _server = server;
      final token = _generateToken();
      _token = token;
      server.listen(_handleRequest);
      return Result.ok(
        LanServerInfo(host: host, port: server.port, token: token),
      );
    } on Exception catch (exception) {
      return Result.err(ServerStartFailure('$exception'));
    }
  }

  @override
  void broadcast(String text) {
    final frame = jsonEncode({'type': 'chat', 'text': text});
    for (final socket in _clients.values) {
      socket.add(frame);
    }
  }

  @override
  Future<void> stop() async {
    for (final socket in [..._clients.values]) {
      await socket.close();
    }
    _clients.clear();
    await _server?.close(force: true);
    _server = null;
    _token = null;
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final authorized =
        request.uri.path == path &&
        _token != null &&
        request.uri.queryParameters['token'] == _token &&
        WebSocketTransformer.isUpgradeRequest(request);
    if (!authorized) {
      request.response.statusCode = HttpStatus.forbidden;
      await request.response.close();
      return;
    }
    final socket = await WebSocketTransformer.upgrade(request);
    final clientId = _nextClientId++;
    _clients[clientId] = socket;
    _events.add(LanClientConnected(clientId: clientId));
    socket.listen(
      (data) => _handleFrame(clientId, socket, data),
      onDone: () => _dropClient(clientId),
      onError: (_) => _dropClient(clientId),
      cancelOnError: true,
    );
  }

  void _handleFrame(int clientId, WebSocket socket, Object? data) {
    if (data is! String) return;
    final Object? decoded;
    try {
      decoded = jsonDecode(data);
    } on FormatException {
      return; // Frame illisible : ignorée, le spike ne casse pas la session.
    }
    if (decoded is! Map<String, Object?>) return;
    switch (decoded['type']) {
      case 'ping':
        socket.add(jsonEncode({'type': 'pong', 'nonce': decoded['nonce']}));
      case 'chat':
        final text = decoded['text'];
        if (text is! String) return;
        _events.add(LanMessageReceived(clientId: clientId, text: text));
        final frame = jsonEncode({'type': 'chat', 'text': text});
        for (final entry in _clients.entries) {
          if (entry.key != clientId) entry.value.add(frame);
        }
      default:
        return; // Type inconnu : toléré (ascendant), ignoré.
    }
  }

  void _dropClient(int clientId) {
    if (_clients.remove(clientId) != null) {
      _events.add(LanClientDisconnected(clientId: clientId));
    }
  }

  static String _generateToken() {
    final random = Random.secure();
    return [
      for (var i = 0; i < 16; i++)
        random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ].join();
  }
}
