import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:notalone/features/session/data/dart_io_host_server.dart';
import 'package:notalone/features/session/domain/host_server.dart';
import 'package:notalone/features/session/domain/protocol/session_close_codes.dart';
import 'package:notalone/features/session/domain/protocol/session_message.dart';
import 'package:notalone/features/session/domain/protocol/session_message_codec.dart';
import 'package:notalone/features/session/domain/session_config.dart';

const _timeout = Duration(seconds: 5);

/// Keepalive et délai de join en millisecondes : le comportement testé est
/// celui des 5 s de production, à l'échelle de temps près.
const _fastConfig = SessionConfig(
  keepaliveInterval: Duration(milliseconds: 100),
  missedPongsBeforeDrop: 2,
  joinTimeout: Duration(milliseconds: 200),
);

/// Invité simulé : un WebSocket brut qui parle le protocole de session, sans
/// rien emprunter au client de MVP-06 (pas encore écrit).
class _Guest {
  _Guest(this.socket)
    : messages = socket
          .map(
            (data) => data is String
                ? SessionMessageCodec.decode(data).valueOrNull
                : null,
          )
          .where((message) => message != null)
          .cast<SessionMessage>()
          .asBroadcastStream() {
    // Draine le flux : sans écoute, un broadcast stream ne bufferise rien et
    // les messages arrivés avant un `first` seraient perdus.
    inbox = <SessionMessage>[];
    messages.listen(
      inbox.add,
      onDone: () {
        _open = false;
        if (!_closed.isCompleted) _closed.complete(socket.closeCode);
      },
    );
  }

  static Future<_Guest> connect(int port) async => _Guest(
    await WebSocket.connect('ws://127.0.0.1:$port${DartIoHostServer.path}'),
  );

  final WebSocket socket;
  final Stream<SessionMessage> messages;
  late final List<SessionMessage> inbox;
  final Completer<int?> _closed = Completer<int?>();
  bool _open = true;

  /// Sans effet une fois le socket fermé : le répondeur automatique de pings
  /// ne doit pas faire échouer un test parce qu'il s'est réveillé après le
  /// départ de l'invité.
  void send(SessionMessage message) {
    if (_open) socket.add(SessionMessageCodec.encode(message));
  }

  /// Répond aux pings de l'hôte, comme le fera le client de MVP-06.
  void answerPings() => messages.listen((message) {
    if (message is Ping) send(Pong(seq: message.seq));
  });

  Future<T> expect<T extends SessionMessage>() =>
      messages.where((message) => message is T).cast<T>().first.timeout(
        _timeout,
      );

  Future<JoinAck> join({
    required String token,
    required String name,
    String? participantId,
  }) {
    final ack = expect<JoinAck>();
    send(
      JoinRequest(
        name: name,
        token: token,
        appVersion: '1.0.0',
        participantId: participantId,
      ),
    );
    return ack;
  }

  /// Code de fermeture envoyé par l'hôte (motif du refus). On attend la fin
  /// du **flux entrant** : `socket.done` ne concerne que le sink sortant et
  /// ne se complète pas tant que l'invité n'a pas fermé de son côté.
  Future<int?> closeCode() => _closed.future.timeout(_timeout);

  Future<void> disconnect() {
    _open = false;
    return socket.close();
  }
}

/// Serveur démarré + collecte de ses événements, refermé en fin de test.
Future<(DartIoHostServer, HostServerInfo, List<HostServerEvent>)> startServer({
  SessionConfig config = const SessionConfig(),
}) async {
  final server = DartIoHostServer(config: config);
  final events = <HostServerEvent>[];
  server.events.listen(events.add);
  final info = (await server.start(hostName: 'Rayan')).valueOrNull;
  expect(info, isNotNull, reason: 'serveur démarré');
  return (server, info!, events);
}

void main() {
  test('join nominal : join_ack, registre et événement', () async {
    final (server, info, events) = await startServer();
    final guest = await _Guest.connect(info.port);

    final ack = await guest.join(token: info.token, name: 'Paul');

    expect(ack.participantId, isNotEmpty);
    expect(ack.participantId, isNot(info.hostParticipant.id));
    expect(ack.colorIndex, 1, reason: 'l hôte a pris la couleur 0');
    expect(ack.clockOffsetProbe, greaterThan(0));
    await pumpEventQueue();
    final joined = events.whereType<ParticipantJoined>().single;
    expect(joined.participant.name, 'Paul');
    expect(joined.isReconnection, isFalse);
    expect(server.participants, hasLength(2), reason: 'hôte + Paul');
    await guest.disconnect();
    await server.endSession();
  });

  test('token invalide → fermeture 4001, aucun participant', () async {
    final (server, info, events) = await startServer();
    final guest = await _Guest.connect(info.port);

    guest.send(
      const JoinRequest(
        name: 'Intrus',
        token: 'mauvais-token',
        appVersion: '1.0.0',
      ),
    );

    expect(await guest.closeCode(), SessionCloseCodes.invalidToken);
    expect(server.participants, hasLength(1), reason: 'l hôte seul');
    expect(
      events.whereType<ParticipantRejected>().single.closeCode,
      SessionCloseCodes.invalidToken,
    );
    await server.endSession();
  });

  test('session pleine : le 8e invité est refusé (4002)', () async {
    final (server, info, events) = await startServer();
    // L'hôte occupe une place : 7 invités remplissent la session.
    for (var i = 0; i < 7; i++) {
      final guest = await _Guest.connect(info.port);
      await guest.join(token: info.token, name: 'invité $i');
    }

    final tooMany = await _Guest.connect(info.port);
    tooMany.send(
      JoinRequest(name: 'le 8e', token: info.token, appVersion: '1.0.0'),
    );

    expect(await tooMany.closeCode(), SessionCloseCodes.sessionFull);
    expect(server.participants, hasLength(8));
    expect(events.whereType<ParticipantJoined>(), hasLength(7));
    expect(events.whereType<ParticipantRejected>(), hasLength(1));
    await server.endSession();
  });

  test('premier message qui n est pas un join_request → 4003', () async {
    final (server, info, _) = await startServer();
    final guest = await _Guest.connect(info.port);

    guest.send(const Ping(seq: 1));

    expect(await guest.closeCode(), SessionCloseCodes.joinExpected);
    await server.endSession();
  });

  test('frame illisible avant le join → 4003', () async {
    final (server, info, _) = await startServer();
    final guest = await _Guest.connect(info.port);

    guest.socket.add('ceci n est pas du JSON');

    expect(await guest.closeCode(), SessionCloseCodes.joinExpected);
    await server.endSession();
  });

  test('socket silencieux → fermé au bout du joinTimeout (4003)', () async {
    final (server, info, _) = await startServer(config: _fastConfig);
    final guest = await _Guest.connect(info.port);

    expect(await guest.closeCode(), SessionCloseCodes.joinExpected);
    await server.endSession();
  });

  group('keepalive', () {
    test('l hôte ping et l invité qui pong reste connecté', () async {
      final (server, info, events) = await startServer(config: _fastConfig);
      final guest = await _Guest.connect(info.port);
      await guest.join(token: info.token, name: 'Paul');
      guest.answerPings();

      await Future<void>.delayed(const Duration(milliseconds: 500));

      expect(guest.inbox.whereType<Ping>().length, greaterThanOrEqualTo(3));
      expect(events.whereType<ParticipantDisconnected>(), isEmpty);
      expect(server.participants.last.isConnected, isTrue);
      await guest.disconnect();
      await server.endSession();
    });

    test('3 pings sans pong → invité déconnecté, socket fermé', () async {
      final (server, info, events) = await startServer(config: _fastConfig);
      final guest = await _Guest.connect(info.port);
      final ack = await guest.join(token: info.token, name: 'Paul');

      await guest.closeCode(); // l'hôte finit par fermer le socket muet

      final dropped = events.whereType<ParticipantDisconnected>().single;
      expect(dropped.participant.id, ack.participantId);
      expect(dropped.participant.isConnected, isFalse);
      expect(
        server.participants,
        hasLength(2),
        reason: 'sa place lui reste réservée',
      );
      await server.endSession();
    });

    test('un ping de l invité reçoit un pong de l hôte', () async {
      final (server, info, _) = await startServer();
      final guest = await _Guest.connect(info.port);
      await guest.join(token: info.token, name: 'Paul');

      guest.send(const Ping(seq: 42));

      expect((await guest.expect<Pong>()).seq, 42);
      await guest.disconnect();
      await server.endSession();
    });
  });

  test('reconnexion : identité et couleur conservées', () async {
    final (server, info, events) = await startServer(config: _fastConfig);
    final first = await _Guest.connect(info.port);
    final ack = await first.join(token: info.token, name: 'Paul');
    await first.disconnect();
    await pumpEventQueue();
    expect(events.whereType<ParticipantDisconnected>(), hasLength(1));
    // Un autre invité prend une place entre-temps.
    final marie = await _Guest.connect(info.port);
    await marie.join(token: info.token, name: 'Marie');

    final back = await _Guest.connect(info.port);
    final backAck = await back.join(
      token: info.token,
      name: 'Paul',
      participantId: ack.participantId,
    );

    expect(backAck.participantId, ack.participantId);
    expect(backAck.colorIndex, ack.colorIndex);
    await pumpEventQueue();
    expect(events.whereType<ParticipantJoined>().last.isReconnection, isTrue);
    expect(server.participants, hasLength(3), reason: 'hôte, Paul, Marie');
    await marie.disconnect();
    await back.disconnect();
    await server.endSession();
  });

  test(
    'reconnexion avant la détection : remplace le socket sans faire sortir',
    () async {
      final (server, info, events) = await startServer();
      final first = await _Guest.connect(info.port);
      final ack = await first.join(token: info.token, name: 'Paul');

      final second = await _Guest.connect(info.port);
      final backAck = await second.join(
        token: info.token,
        name: 'Paul',
        participantId: ack.participantId,
      );

      expect(backAck.participantId, ack.participantId);
      await first.closeCode(); // l'ancien socket est abandonné par l'hôte
      await pumpEventQueue();
      expect(
        events.whereType<ParticipantDisconnected>(),
        isEmpty,
        reason: 'Paul n a jamais quitté la session',
      );
      expect(server.participants, hasLength(2));
      expect(server.participants.last.isConnected, isTrue);
      await second.disconnect();
      await server.endSession();
    },
  );

  group('messages applicatifs', () {
    test('speech_segment et mic_status remontent attribués', () async {
      final (server, info, events) = await startServer();
      final guest = await _Guest.connect(info.port);
      final ack = await guest.join(token: info.token, name: 'Paul');

      guest
        ..send(
          const SpeechSegmentDto(
            segmentId: 's1',
            tStartMs: 1000,
            tEndMs: 2000,
            text: 'bonjour tout le monde',
            isFinal: true,
            energyDb: -18.5,
            engine: 'ios_native',
          ),
        )
        ..send(const MicStatus(state: MicStatusState.muted, batteryPct: 42));
      await pumpEventQueue();

      final received = events.whereType<SessionMessageReceived>().toList();
      expect(received, hasLength(2));
      expect(received.every((e) => e.participantId == ack.participantId), true);
      expect(
        (received.first.message as SpeechSegmentDto).text,
        'bonjour tout le monde',
      );
      expect((received.last.message as MicStatus).batteryPct, 42);
      await guest.disconnect();
      await server.endSession();
    });

    test('frame illisible en session : ignorée, la session continue', () async {
      final (server, info, events) = await startServer();
      final guest = await _Guest.connect(info.port);
      await guest.join(token: info.token, name: 'Paul');

      guest.socket.add('{"v":1,"type":"venu_du_futur","payload":{}}');
      guest.socket.add('pas du JSON');
      guest.send(const Ping(seq: 7));

      expect((await guest.expect<Pong>()).seq, 7, reason: 'toujours en vie');
      expect(events.whereType<SessionMessageReceived>(), isEmpty);
      expect(events.whereType<ParticipantDisconnected>(), isEmpty);
      await guest.disconnect();
      await server.endSession();
    });

    test('broadcast et sendTo', () async {
      final (server, info, _) = await startServer();
      final paul = await _Guest.connect(info.port);
      final marie = await _Guest.connect(info.port);
      final paulAck = await paul.join(token: info.token, name: 'Paul');
      await marie.join(token: info.token, name: 'Marie');

      final paulPong = paul.expect<Pong>();
      final mariePong = marie.expect<Pong>();
      server.broadcast(const Pong(seq: 1));
      expect((await paulPong).seq, 1);
      expect((await mariePong).seq, 1);

      final onlyPaul = paul.expect<ClockSync>();
      server.sendTo(
        paulAck.participantId,
        const ClockSync(seq: 0, tHostSentMs: 5),
      );
      expect((await onlyPaul).seq, 0);
      await pumpEventQueue();
      expect(marie.inbox.whereType<ClockSync>(), isEmpty);

      await paul.disconnect();
      await marie.disconnect();
      await server.endSession();
    });
  });

  test('session_end : diffusé à tous, état serveur effacé', () async {
    final (server, info, _) = await startServer();
    final paul = await _Guest.connect(info.port);
    final marie = await _Guest.connect(info.port);
    await paul.join(token: info.token, name: 'Paul');
    await marie.join(token: info.token, name: 'Marie');
    final paulEnd = paul.expect<SessionEnd>();
    final marieEnd = marie.expect<SessionEnd>();

    await server.endSession();

    expect(await paulEnd, const SessionEnd());
    expect(await marieEnd, const SessionEnd());
    expect(await paul.closeCode(), SessionCloseCodes.sessionEnded);
    expect(await marie.closeCode(), SessionCloseCodes.sessionEnded);
    expect(server.participants, isEmpty, reason: 'aucune trace conservée');
    await expectLater(
      _Guest.connect(info.port),
      throwsA(anything),
      reason: 'le port n écoute plus',
    );
  });

  test('endSession est idempotent', () async {
    final (server, _, _) = await startServer();

    await server.endSession();
    await server.endSession();
  });
}
