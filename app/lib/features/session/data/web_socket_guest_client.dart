import 'dart:async';
import 'dart:collection';

import 'package:notalone/core/app_info.dart';
import 'package:notalone/core/result/failure.dart';
import 'package:notalone/core/result/result.dart';
import 'package:notalone/features/session/domain/guest_client.dart';
import 'package:notalone/features/session/domain/guest_config.dart';
import 'package:notalone/features/session/domain/protocol/session_close_codes.dart';
import 'package:notalone/features/session/domain/protocol/session_message.dart';
import 'package:notalone/features/session/domain/protocol/session_message_codec.dart';
import 'package:notalone/features/session/domain/protocol/session_wire.dart';
import 'package:notalone/features/session/domain/qr_session_payload.dart';
import 'package:notalone/features/session/domain/session_failure.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Client WebSocket de l'invité (`web_socket_channel`), pendant du
/// `DartIoHostServer` (cf. cowork/02-architecture.md §4).
///
/// Il tient trois choses que l'UI n'a pas à connaître : le keepalive (répondre
/// `pong` aux `ping` de l'hôte, faute de quoi l'hôte le déclare parti au bout
/// de 3 pings), la reconnexion automatique en rejouant le `join_request` avec
/// le `participantId` obtenu — c'est ce qui lui rend sa couleur et sa place —
/// et la file d'envoi qui absorbe les messages produits pendant la coupure.
class WebSocketGuestClient implements GuestClient {
  WebSocketGuestClient({
    this._config = const GuestConfig(),
    this._appVersion = AppInfo.version,
  });

  final GuestConfig _config;
  final String _appVersion;

  final StreamController<GuestClientEvent> _events =
      StreamController<GuestClientEvent>.broadcast();

  /// Messages produits alors que le socket était coupé, réémis dans l'ordre à
  /// la reconnexion.
  final Queue<SessionMessage> _outbox = Queue<SessionMessage>();

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Completer<Result<GuestSession>>? _pendingJoin;
  Timer? _reconnectTimer;

  QrSessionPayload? _target;
  String? _name;
  GuestSession? _session;
  int _reconnectAttempt = 0;
  bool _leaving = false;
  bool _ended = false;

  @override
  Stream<GuestClientEvent> get events => _events.stream;

  @override
  GuestSession? get session => _session;

  @override
  Future<Result<GuestSession>> join({
    required QrSessionPayload session,
    required String name,
  }) async {
    // Changer de session, c'est repartir de zéro : garder l'identité obtenue
    // d'un autre hôte n'aurait aucun sens, et les messages en attente non plus.
    if (_target != session) {
      _session = null;
      _outbox.clear();
    }
    _target = session;
    _name = name;
    _leaving = false;
    _ended = false;
    _reconnectAttempt = 0;
    return _openAndJoin();
  }

  @override
  void send(SessionMessage message) {
    final channel = _channel;
    if (channel == null || _session == null) {
      if (_outbox.length >= _config.maxQueuedMessages) _outbox.removeFirst();
      _outbox.add(message);
      return;
    }
    channel.sink.add(SessionMessageCodec.encode(message));
  }

  @override
  Future<void> leave() async {
    _leaving = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _closeChannel();
    _outbox.clear();
    _session = null;
    _reconnectAttempt = 0;
  }

  @override
  Future<void> dispose() async {
    await leave();
    if (!_events.isClosed) await _events.close();
  }

  /// Ouvre un socket et joue le `join_request`. Utilisé aussi bien pour la
  /// première entrée que pour chaque tentative de reconnexion.
  Future<Result<GuestSession>> _openAndJoin() async {
    final target = _target;
    final name = _name;
    if (target == null || name == null) {
      return const Result.err(ConnectionFailure('session inconnue'));
    }
    final WebSocketChannel channel;
    try {
      channel = WebSocketChannel.connect(
        SessionWire.uriFor(host: target.host, port: target.port),
      );
      await channel.ready.timeout(_config.connectTimeout);
    } on TimeoutException {
      return const Result.err(ConnectionTimeoutFailure());
    } on Exception catch (exception) {
      return Result.err(ConnectionFailure('$exception'));
    }

    _channel = channel;
    final pending = Completer<Result<GuestSession>>();
    _pendingJoin = pending;
    _subscription = channel.stream.listen(
      _handleFrame,
      onDone: () => _handleClosed(channel),
      onError: (_) => _handleClosed(channel),
      cancelOnError: true,
    );
    channel.sink.add(
      SessionMessageCodec.encode(
        JoinRequest(
          name: name,
          token: target.token,
          appVersion: _appVersion,
          // Absent au premier join, présent ensuite : c'est le jeton de
          // reprise d'identité (cf. `JoinRequest.participantId`).
          participantId: _session?.participantId,
        ),
      ),
    );

    try {
      return await pending.future.timeout(_config.joinAckTimeout);
    } on TimeoutException {
      await _closeChannel();
      return const Result.err(ConnectionTimeoutFailure());
    } finally {
      _pendingJoin = null;
    }
  }

  void _handleFrame(Object? data) {
    if (data is! String) return;
    final decoded = SessionMessageCodec.decode(data);
    // Frame illisible ou type inconnu : ignorée, la session continue
    // (tolérance ascendante, doc 02 §4).
    if (decoded case Ok(value: final message)) _handleMessage(message);
  }

  void _handleMessage(SessionMessage message) {
    switch (message) {
      case Ping(:final seq):
        _channel?.sink.add(SessionMessageCodec.encode(Pong(seq: seq)));
      case JoinAck(
        :final participantId,
        :final colorIndex,
        :final clockOffsetProbe,
      ):
        _completeJoin(
          Result.ok(
            GuestSession(
              participantId: participantId,
              colorIndex: colorIndex,
              clockOffsetProbe: clockOffsetProbe,
            ),
          ),
        );
      case SessionEnd():
        _ended = true;
        _emit(const GuestSessionEnded());
        unawaited(_closeChannel());
      case Pong():
        return; // L'invité n'émet pas de ping : rien à apparier.
      case ClockSync() || JoinRequest() || MicStatus() || SpeechSegmentDto():
        _emit(GuestMessageReceived(message));
    }
  }

  void _completeJoin(Result<GuestSession> result) {
    if (result case Ok(value: final session)) {
      final isReconnection = _session != null;
      _session = session;
      _reconnectAttempt = 0;
      _flushOutbox();
      if (isReconnection) _emit(GuestReconnected(session));
    }
    final pending = _pendingJoin;
    if (pending != null && !pending.isCompleted) pending.complete(result);
  }

  void _flushOutbox() {
    final channel = _channel;
    if (channel == null) return;
    while (_outbox.isNotEmpty) {
      channel.sink.add(SessionMessageCodec.encode(_outbox.removeFirst()));
    }
  }

  /// Socket fermé : soit l'hôte refuse (code de fermeture applicatif), soit la
  /// connexion est tombée. Le `join` en cours reçoit sa `Failure`, et une
  /// reconnexion est programmée si la coupure était subie.
  void _handleClosed(WebSocketChannel channel) {
    if (!identical(_channel, channel)) return;
    final closeCode = channel.closeCode;
    _channel = null;
    unawaited(_subscription?.cancel());
    _subscription = null;

    final failure = _failureFor(closeCode);
    final pending = _pendingJoin;
    if (pending != null && !pending.isCompleted) {
      // Une tentative est en cours : c'est elle qui décide de la suite
      // (première entrée → l'appelant voit l'échec ; reconnexion → la boucle
      // de backoff enchaîne). Programmer ici en plus doublerait les essais.
      pending.complete(Result.err(failure));
      return;
    }
    if (_leaving || _ended) return;
    if (_session == null) return; // Jamais entré : c'est `join` qui répond.
    _scheduleReconnect(failure);
  }

  static Failure _failureFor(int? closeCode) => switch (closeCode) {
    null => const ConnectionFailure('connexion fermée'),
    SessionCloseCodes.sessionEnded => JoinRefusedFailure(
      SessionCloseCodes.sessionEnded,
    ),
    final int code when code >= 4000 && code <= 4999 => JoinRefusedFailure(
      code,
    ),
    _ => const ConnectionFailure('connexion fermée'),
  };

  void _scheduleReconnect(Failure lastFailure) {
    // Un QR périmé ne redeviendra pas valide : l'hôte a redémarré avec un
    // autre token, s'acharner ne ferait que vider la batterie.
    if (lastFailure is JoinRefusedFailure &&
        lastFailure.closeCode != SessionCloseCodes.sessionFull) {
      _giveUp(lastFailure);
      return;
    }
    if (_reconnectAttempt >= _config.reconnectBackoff.length) {
      _giveUp(lastFailure);
      return;
    }
    final delay = _config.reconnectBackoff[_reconnectAttempt];
    _reconnectAttempt++;
    _emit(GuestReconnecting(attempt: _reconnectAttempt, delay: delay));
    _reconnectTimer = Timer(delay, () async {
      _reconnectTimer = null;
      if (_leaving || _ended) return;
      final result = await _openAndJoin();
      if (result case Err(:final failure)) _scheduleReconnect(failure);
    });
  }

  void _giveUp(Failure failure) {
    _reconnectAttempt = 0;
    _emit(GuestConnectionLost(failure));
  }

  Future<void> _closeChannel() async {
    final channel = _channel;
    _channel = null;
    await _subscription?.cancel();
    _subscription = null;
    await channel?.sink.close();
  }

  void _emit(GuestClientEvent event) {
    if (!_events.isClosed) _events.add(event);
  }
}
