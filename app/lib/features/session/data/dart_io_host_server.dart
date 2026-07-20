import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:notalone/core/result/result.dart';
import 'package:notalone/features/session/data/local_ip.dart';
import 'package:notalone/features/session/domain/host_server.dart';
import 'package:notalone/features/session/domain/participant.dart';
import 'package:notalone/features/session/domain/participant_registry.dart';
import 'package:notalone/features/session/domain/protocol/session_close_codes.dart';
import 'package:notalone/features/session/domain/protocol/session_message.dart';
import 'package:notalone/features/session/domain/protocol/session_message_codec.dart';
import 'package:notalone/features/session/domain/protocol/session_wire.dart';
import 'package:notalone/features/session/domain/session_config.dart';
import 'package:notalone/features/session/domain/session_failure.dart';

/// Serveur WebSocket `dart:io` de la session hôte (cf. cowork/02-architecture.md
/// §4).
///
/// Écart assumé vs le spike MVP-03 : le token ne circule plus en query string
/// à l'upgrade mais se vérifie dans le `join_request`, au niveau du protocole.
/// Il ne traîne donc ni dans les URLs ni dans les journaux, et un socket qui
/// n'annonce rien d'exploitable dans `joinTimeout` est fermé (4003).
class DartIoHostServer implements HostServer {
  DartIoHostServer({
    SessionConfig config = const SessionConfig(),
    ParticipantRegistry? registry,
  }) : _config = config,
       _registry = registry ?? ParticipantRegistry(config: config);

  final SessionConfig _config;
  final ParticipantRegistry _registry;
  final StreamController<HostServerEvent> _events =
      StreamController<HostServerEvent>.broadcast();

  /// Connexions admises, indexées par `participantId` : un invité n'a qu'un
  /// socket courant, une reconnexion remplace le précédent.
  final Map<String, _Connection> _connections = {};

  HttpServer? _server;
  String? _token;
  bool _ended = false;

  @override
  Stream<HostServerEvent> get events => _events.stream;

  @override
  List<Participant> get participants => _registry.participants;

  @override
  Future<Result<HostServerInfo>> start({required String hostName}) async {
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
      final hostParticipant = _registry.registerHost(hostName);
      server.listen(_handleRequest);
      return Result.ok(
        HostServerInfo(
          host: host,
          port: server.port,
          token: token,
          hostParticipant: hostParticipant,
        ),
      );
    } on Exception catch (exception) {
      return Result.err(ServerStartFailure('$exception'));
    }
  }

  @override
  void broadcast(SessionMessage message) {
    final frame = SessionMessageCodec.encode(message);
    for (final connection in [..._connections.values]) {
      connection.socket.add(frame);
    }
  }

  @override
  void sendTo(String participantId, SessionMessage message) {
    _connections[participantId]?.socket.add(
      SessionMessageCodec.encode(message),
    );
  }

  @override
  Future<void> endSession() async {
    if (_ended) return;
    _ended = true;
    broadcast(const SessionEnd());
    for (final connection in [..._connections.values]) {
      await connection.closeWith(
        SessionCloseCodes.sessionEnded,
        'session terminée',
      );
    }
    _connections.clear();
    _registry.clear();
    await _server?.close(force: true);
    _server = null;
    _token = null;
    await _events.close();
  }

  Future<void> _handleRequest(HttpRequest request) async {
    if (request.uri.path != SessionWire.path ||
        !WebSocketTransformer.isUpgradeRequest(request)) {
      request.response.statusCode = HttpStatus.forbidden;
      await request.response.close();
      return;
    }
    final socket = await WebSocketTransformer.upgrade(request);
    // Le socket n'existe pour la session qu'une fois son `join_request`
    // validé : jusque-là il n'a ni participant ni place réservée.
    final connection = _Connection(socket: socket)
      ..listen(onFrame: _onFrame, onClosed: _onClosed);
    connection.startJoinDeadline(
      _config.joinTimeout,
      () => _reject(
        connection,
        SessionCloseCodes.joinExpected,
        'aucun join_request reçu',
      ),
    );
  }

  void _onFrame(_Connection connection, SessionMessage? message) {
    if (connection.participantId == null) {
      _handleJoinFrame(connection, message);
      return;
    }
    // Frame illisible ou type inconnu en cours de session : ignorée, la
    // session continue (tolérance ascendante, doc 02 §4).
    if (message != null) _handleMessage(connection, message);
  }

  /// Le premier message doit être un `join_request` valide : tout le reste
  /// (JSON illisible, autre type, payload malformé) vaut refus — hors session,
  /// la tolérance ascendante n'a rien à quoi se raccrocher.
  void _handleJoinFrame(_Connection connection, SessionMessage? message) {
    connection.cancelJoinDeadline();
    if (message is! JoinRequest) {
      _reject(
        connection,
        SessionCloseCodes.joinExpected,
        'premier message : join_request attendu',
      );
      return;
    }
    if (message.token != _token) {
      _reject(connection, SessionCloseCodes.invalidToken, 'token invalide');
      return;
    }
    final admission = _registry.join(
      name: message.name,
      participantId: message.participantId,
    );
    switch (admission) {
      case Err(:final failure):
        _reject(connection, SessionCloseCodes.sessionFull, failure.message);
      case Ok(value: final participant):
        _admit(
          connection: connection,
          participant: participant,
          isReconnection: message.participantId == participant.id,
        );
    }
  }

  void _admit({
    required _Connection connection,
    required Participant participant,
    required bool isReconnection,
  }) {
    // Reconnexion arrivée avant que le keepalive n'ait constaté le départ :
    // le socket précédent est abandonné sans émettre de déconnexion.
    unawaited(_connections.remove(participant.id)?.closeWith(null, null));

    connection.participantId = participant.id;
    _connections[participant.id] = connection;
    connection.socket.add(
      SessionMessageCodec.encode(
        JoinAck(
          participantId: participant.id,
          colorIndex: participant.colorIndex,
          // Probe n°0 de la synchronisation d'horloge, exploitée en MVP-09.
          clockOffsetProbe: DateTime.now().millisecondsSinceEpoch,
        ),
      ),
    );
    connection.startKeepalive(
      interval: _config.keepaliveInterval,
      missedPongsBeforeDrop: _config.missedPongsBeforeDrop,
      onExpired: () => _onClosed(connection),
    );
    _emit(
      ParticipantJoined(
        participant: participant,
        isReconnection: isReconnection,
      ),
    );
  }

  void _handleMessage(_Connection connection, SessionMessage message) {
    switch (message) {
      case Ping(:final seq):
        connection.socket.add(SessionMessageCodec.encode(Pong(seq: seq)));
      case Pong():
        connection.onPong();
      case JoinRequest():
        return; // Déjà admis : un second join sur le même socket est ignoré.
      case ClockSync() ||
          JoinAck() ||
          MicStatus() ||
          SessionEnd() ||
          SpeechSegmentDto():
        _emit(
          SessionMessageReceived(
            participantId: connection.participantId!,
            message: message,
          ),
        );
    }
  }

  /// Ne déconnecte que si le socket est bien la connexion courante du
  /// participant : un socket abandonné par reconnexion se ferme après coup et
  /// ne doit pas faire sortir l'invité qui vient de revenir.
  void _onClosed(_Connection connection) {
    final participantId = connection.participantId;
    if (participantId == null) {
      connection.cancelJoinDeadline();
      return;
    }
    if (!identical(_connections[participantId], connection)) return;
    _connections.remove(participantId);
    unawaited(connection.closeWith(null, null));
    final disconnected = _registry.markDisconnected(participantId);
    if (disconnected != null) _emit(ParticipantDisconnected(disconnected));
  }

  void _reject(_Connection connection, int closeCode, String reason) {
    _emit(ParticipantRejected(reason: reason, closeCode: closeCode));
    unawaited(connection.closeWith(closeCode, reason));
  }

  void _emit(HostServerEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  static String _generateToken() {
    final random = Random.secure();
    return [
      for (var i = 0; i < 16; i++)
        random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ].join();
  }
}

/// Socket d'un invité + son keepalive. Tant que [participantId] est nul, la
/// connexion est en attente de `join_request` et ne compte pour rien dans la
/// session. Une fois admise, l'hôte envoie un `ping` par période et déclare
/// l'invité parti après `missedPongsBeforeDrop` pings sans réponse (doc 02 §4).
class _Connection {
  _Connection({required this.socket});

  final WebSocket socket;

  String? participantId;

  StreamSubscription<dynamic>? _subscription;
  Timer? _joinDeadline;
  Timer? _keepalive;
  int _pingSeq = 0;
  int _missedPongs = 0;

  void listen({
    required void Function(_Connection connection, SessionMessage? message)
    onFrame,
    required void Function(_Connection connection) onClosed,
  }) {
    _subscription = socket.listen(
      (data) => onFrame(
        this,
        data is String ? SessionMessageCodec.decode(data).valueOrNull : null,
      ),
      onDone: () => onClosed(this),
      onError: (_) => onClosed(this),
      cancelOnError: true,
    );
  }

  void startJoinDeadline(Duration timeout, void Function() onExpired) {
    _joinDeadline = Timer(timeout, onExpired);
  }

  void cancelJoinDeadline() {
    _joinDeadline?.cancel();
    _joinDeadline = null;
  }

  void startKeepalive({
    required Duration interval,
    required int missedPongsBeforeDrop,
    required void Function() onExpired,
  }) {
    _keepalive = Timer.periodic(interval, (_) {
      if (_missedPongs >= missedPongsBeforeDrop) {
        onExpired();
        return;
      }
      _missedPongs++;
      socket.add(SessionMessageCodec.encode(Ping(seq: _pingSeq++)));
    });
  }

  void onPong() => _missedPongs = 0;

  /// Ferme le socket **avant** d'annuler l'abonnement : sur un WebSocket
  /// `dart:io` qui n'a encore rien reçu, `cancel()` ne rend la main qu'une
  /// fois le flux terminé — l'annuler d'abord bloquait la fermeture d'un
  /// socket resté muet (refus 4003).
  Future<void> closeWith(int? closeCode, String? reason) async {
    cancelJoinDeadline();
    _keepalive?.cancel();
    _keepalive = null;
    await socket.close(closeCode, reason);
    await _subscription?.cancel();
    _subscription = null;
  }
}
