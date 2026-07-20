import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:notalone/features/session/data/dart_io_host_server.dart';
import 'package:notalone/features/session/data/web_socket_guest_client.dart';
import 'package:notalone/features/session/domain/guest_client.dart';
import 'package:notalone/features/session/domain/guest_config.dart';
import 'package:notalone/features/session/domain/host_server.dart';
import 'package:notalone/features/session/domain/protocol/session_close_codes.dart';
import 'package:notalone/features/session/domain/protocol/session_message.dart';
import 'package:notalone/features/session/domain/qr_session_payload.dart';
import 'package:notalone/features/session/domain/session_config.dart';
import 'package:notalone/features/session/domain/session_failure.dart';

const _timeout = Duration(seconds: 5);

/// Keepalive et backoff en millisecondes : le comportement testé est celui de
/// la production (5 s de keepalive, 1/2/4 s de backoff), à l'échelle de temps
/// près.
const _fastServer = SessionConfig(
  keepaliveInterval: Duration(milliseconds: 60),
  missedPongsBeforeDrop: 2,
  joinTimeout: Duration(milliseconds: 500),
);

const _fastGuest = GuestConfig(
  connectTimeout: Duration(seconds: 2),
  joinAckTimeout: Duration(seconds: 2),
  reconnectBackoff: [
    Duration(milliseconds: 20),
    Duration(milliseconds: 40),
    Duration(milliseconds: 60),
  ],
);

/// Coupure réseau reproductible : un relais TCP entre l'invité et l'hôte.
/// [cut] détruit les connexions en cours comme un WiFi qui tombe, sans que
/// l'hôte ni le client ne changent d'adresse — c'est bien la même session que
/// l'invité doit retrouver.
class _LanProxy {
  _LanProxy._(this._server, this.target);

  final ServerSocket _server;

  /// Même adresse pour l'invité, autre serveur derrière quand on la change :
  /// c'est ce que voit un invité dont l'hôte a redémarré sa session.
  int target;
  final List<Socket> _live = [];
  bool _accepting = true;

  static Future<_LanProxy> start(int targetPort) async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final proxy = _LanProxy._(server, targetPort);
    server.listen((socket) => unawaited(proxy._handle(socket)));
    return proxy;
  }

  int get port => _server.port;

  Future<void> _handle(Socket incoming) async {
    if (!_accepting) {
      incoming.destroy();
      return;
    }
    final Socket outgoing;
    try {
      outgoing = await Socket.connect(
        InternetAddress.loopbackIPv4,
        target,
      );
    } on SocketException {
      incoming.destroy();
      return;
    }
    _live
      ..add(incoming)
      ..add(outgoing);
    incoming.listen(
      outgoing.add,
      onDone: outgoing.destroy,
      onError: (_) => outgoing.destroy(),
      cancelOnError: true,
    );
    outgoing.listen(
      incoming.add,
      onDone: incoming.destroy,
      onError: (_) => incoming.destroy(),
      cancelOnError: true,
    );
  }

  void cut() {
    for (final socket in _live) {
      socket.destroy();
    }
    _live.clear();
  }

  /// L'hôte devient injoignable pour de bon (téléphone éteint, session finie).
  void refuseNewConnections() => _accepting = false;

  Future<void> dispose() async {
    cut();
    await _server.close();
  }
}

/// Session hôte démarrée + collecte de ses événements.
Future<(DartIoHostServer, HostServerInfo, List<HostServerEvent>)> startHost({
  SessionConfig config = _fastServer,
}) async {
  final server = DartIoHostServer(config: config);
  final events = <HostServerEvent>[];
  server.events.listen(events.add);
  final info = (await server.start(hostName: 'Rayan')).valueOrNull;
  expect(info, isNotNull, reason: 'le serveur doit démarrer');
  return (server, info!, events);
}

/// Le QR pointe vers l'adresse LAN de l'hôte ; en test on passe par la
/// boucle locale (ou par le relais, quand on veut couper le réseau).
QrSessionPayload payloadFor(HostServerInfo info, {int? port}) =>
    QrSessionPayload(
      sessionName: 'Repas',
      host: '127.0.0.1',
      port: port ?? info.port,
      token: info.token,
    );

Future<T> firstEvent<T extends GuestClientEvent>(GuestClient client) => client
    .events
    .where((event) => event is T)
    .cast<T>()
    .first
    .timeout(
      _timeout,
    );

void main() {
  group('entrée en session', () {
    test('join valide → identité et couleur attribuées par l’hôte', () async {
      final (server, info, events) = await startHost();
      final client = WebSocketGuestClient(config: _fastGuest);
      addTearDown(() async {
        await client.dispose();
        await server.endSession();
      });

      final joined = await client.join(
        session: payloadFor(info),
        name: 'Camille',
      );

      final session = joined.valueOrNull;
      expect(session, isNotNull);
      expect(session!.participantId, isNotEmpty);
      expect(client.session, session);
      await pumpEventQueue();
      final joinedEvent = events.whereType<ParticipantJoined>().single;
      expect(joinedEvent.participant.name, 'Camille');
      expect(joinedEvent.isReconnection, isFalse);
      expect(session.colorIndex, joinedEvent.participant.colorIndex);
    });

    test('token invalide → refus typé porteur du code 4001', () async {
      final (server, info, _) = await startHost();
      final client = WebSocketGuestClient(config: _fastGuest);
      addTearDown(() async {
        await client.dispose();
        await server.endSession();
      });

      final joined = await client.join(
        session: QrSessionPayload(
          sessionName: 'Repas',
          host: '127.0.0.1',
          port: info.port,
          token: 'mauvais-token',
        ),
        name: 'Camille',
      );

      final failure = joined.failureOrNull;
      expect(failure, isA<JoinRefusedFailure>());
      expect(
        (failure! as JoinRefusedFailure).closeCode,
        SessionCloseCodes.invalidToken,
      );
      expect(client.session, isNull);
    });

    test('session pleine → refus typé porteur du code 4002', () async {
      // 2 places : l'hôte en occupe une, le premier invité la seconde.
      final (server, info, _) = await startHost(
        config: const SessionConfig(
          maxParticipants: 2,
          keepaliveInterval: Duration(milliseconds: 60),
          joinTimeout: Duration(milliseconds: 500),
        ),
      );
      final first = WebSocketGuestClient(config: _fastGuest);
      final second = WebSocketGuestClient(config: _fastGuest);
      addTearDown(() async {
        await first.dispose();
        await second.dispose();
        await server.endSession();
      });

      final accepted = await first.join(
        session: payloadFor(info),
        name: 'Camille',
      );
      final refused = await second.join(
        session: payloadFor(info),
        name: 'Paul',
      );

      expect(accepted.isOk, isTrue);
      final failure = refused.failureOrNull;
      expect(failure, isA<JoinRefusedFailure>());
      expect(
        (failure! as JoinRefusedFailure).closeCode,
        SessionCloseCodes.sessionFull,
      );
    });

    test('hôte injoignable → timeout typé (cas R7 du doc 03)', () async {
      final client = WebSocketGuestClient(
        config: const GuestConfig(
          connectTimeout: Duration(milliseconds: 200),
          joinAckTimeout: Duration(milliseconds: 200),
        ),
      );
      addTearDown(client.dispose);

      // Adresse non routable : la connexion n'aboutit jamais, comme sur un
      // WiFi qui isole les clients entre eux.
      final joined = await client.join(
        session: const QrSessionPayload(
          sessionName: 'Repas',
          host: '10.255.255.1',
          port: 40000,
          token: 'tok',
        ),
        name: 'Camille',
      );

      expect(joined.failureOrNull, isA<SessionFailure>());
      expect(joined.isErr, isTrue);
    });
  });

  group('vie de la session', () {
    test(
      'le client répond aux pings : l’hôte ne le déclare pas parti',
      () async {
        final (server, info, events) = await startHost();
        final client = WebSocketGuestClient(config: _fastGuest);
        addTearDown(() async {
          await client.dispose();
          await server.endSession();
        });

        await client.join(session: payloadFor(info), name: 'Camille');
        // Plusieurs périodes de keepalive : sans `pong`, l'hôte laisserait
        // tomber l'invité au bout de 2 pings manqués.
        await Future<void>.delayed(const Duration(milliseconds: 400));

        expect(events.whereType<ParticipantDisconnected>(), isEmpty);
        final guest = server.participants.firstWhere(
          (participant) => !participant.isHost,
        );
        expect(guest.isConnected, isTrue);
      },
    );

    test('les messages de l’invité parviennent à l’hôte', () async {
      final (server, info, events) = await startHost();
      final client = WebSocketGuestClient(config: _fastGuest);
      addTearDown(() async {
        await client.dispose();
        await server.endSession();
      });

      await client.join(session: payloadFor(info), name: 'Camille');
      client.send(
        const MicStatus(state: MicStatusState.active, batteryPct: 80),
      );
      await pumpEventQueue();

      final received = events.whereType<SessionMessageReceived>().single;
      expect(received.message, isA<MicStatus>());
    });

    test('fin de session côté hôte → l’invité en est informé', () async {
      final (server, info, _) = await startHost();
      final client = WebSocketGuestClient(config: _fastGuest);
      addTearDown(client.dispose);

      await client.join(session: payloadFor(info), name: 'Camille');
      final ended = firstEvent<GuestSessionEnded>(client);
      await server.endSession();

      await ended;
      // Session close : aucune reconnexion ne doit être tentée.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(
        await client.events
            .where((event) => event is GuestReconnecting)
            .isEmpty
            .timeout(const Duration(milliseconds: 100), onTimeout: () => true),
        isTrue,
      );
    });
  });

  group('coupure réseau', () {
    test(
      'coupure puis retour → reconnexion transparente, identité conservée',
      () async {
        final (server, info, events) = await startHost();
        final proxy = await _LanProxy.start(info.port);
        final client = WebSocketGuestClient(config: _fastGuest);
        addTearDown(() async {
          await client.dispose();
          await proxy.dispose();
          await server.endSession();
        });

        final joined = await client.join(
          session: payloadFor(info, port: proxy.port),
          name: 'Camille',
        );
        final identity = joined.valueOrNull!;

        final reconnected = firstEvent<GuestReconnected>(client);
        proxy.cut();
        final session = (await reconnected).session;

        expect(session.participantId, identity.participantId);
        expect(session.colorIndex, identity.colorIndex);
        await pumpEventQueue();
        final joins = events.whereType<ParticipantJoined>().toList();
        expect(joins, hasLength(2));
        expect(joins.last.isReconnection, isTrue);
        expect(
          server.participants.map((participant) => participant.name),
          ['Rayan', 'Camille'],
          reason: 'aucun doublon : l’invité a repris sa place',
        );
      },
    );

    test(
      'les messages produits pendant la coupure partent à la reprise',
      () async {
        final (server, info, events) = await startHost();
        final proxy = await _LanProxy.start(info.port);
        final client = WebSocketGuestClient(config: _fastGuest);
        addTearDown(() async {
          await client.dispose();
          await proxy.dispose();
          await server.endSession();
        });

        await client.join(
          session: payloadFor(info, port: proxy.port),
          name: 'Camille',
        );
        final reconnecting = firstEvent<GuestReconnecting>(client);
        final reconnected = firstEvent<GuestReconnected>(client);
        proxy.cut();
        // Une fois la coupure *constatée* : un message émis dans la poignée de
        // millisecondes où le socket paraît encore vivant part sur un tuyau
        // mort, et TCP ne permet pas de le savoir. C'est la file qui garantit
        // l'acheminement à partir de là.
        await reconnecting;
        client.send(
          const MicStatus(state: MicStatusState.muted, batteryPct: 42),
        );
        await reconnected;
        await pumpEventQueue();

        final received = events
            .whereType<SessionMessageReceived>()
            .map((event) => event.message)
            .whereType<MicStatus>();
        expect(received, hasLength(1));
        expect(received.single.batteryPct, 42);
      },
    );

    test(
      'hôte définitivement injoignable → abandon après le backoff',
      () async {
        final (server, info, _) = await startHost();
        final proxy = await _LanProxy.start(info.port);
        final client = WebSocketGuestClient(config: _fastGuest);
        addTearDown(() async {
          await client.dispose();
          await proxy.dispose();
          await server.endSession();
        });

        await client.join(
          session: payloadFor(info, port: proxy.port),
          name: 'Camille',
        );
        final attempts = <GuestReconnecting>[];
        final subscription = client.events.listen((event) {
          if (event is GuestReconnecting) attempts.add(event);
        });
        addTearDown(subscription.cancel);
        final lost = firstEvent<GuestConnectionLost>(client);
        proxy
          ..refuseNewConnections()
          ..cut();

        await lost;
        expect(
          attempts.length,
          _fastGuest.reconnectBackoff.length,
          reason: 'une tentative par palier de backoff, puis abandon',
        );
        expect(
          attempts.map((event) => event.delay),
          _fastGuest.reconnectBackoff,
          reason: 'les paliers sont respectés dans l’ordre',
        );
      },
    );

    test('QR périmé après redémarrage de l’hôte → abandon immédiat', () async {
      final (server, info, _) = await startHost();
      final proxy = await _LanProxy.start(info.port);
      final client = WebSocketGuestClient(config: _fastGuest);
      addTearDown(() async {
        await client.dispose();
        await proxy.dispose();
        await server.endSession();
      });

      await client.join(
        session: payloadFor(info, port: proxy.port),
        name: 'Camille',
      );
      final lost = firstEvent<GuestConnectionLost>(client);
      final attempts = <GuestReconnecting>[];
      final subscription = client.events.listen((event) {
        if (event is GuestReconnecting) attempts.add(event);
      });
      addTearDown(subscription.cancel);

      // On coupe d'abord : l'invité ne reçoit pas le `session_end` et croit à
      // une coupure réseau. L'hôte repart alors de zéro — nouveau token,
      // l'ancien QR ne vaut plus rien.
      proxy.cut();
      await server.endSession();
      final (restarted, restartedInfo, _) = await startHost();
      addTearDown(restarted.endSession);
      proxy.target = restartedInfo.port;

      final failure = (await lost).failure;
      expect(failure, isA<JoinRefusedFailure>());
      expect(
        (failure as JoinRefusedFailure).closeCode,
        SessionCloseCodes.invalidToken,
      );
      expect(
        attempts.length,
        lessThan(_fastGuest.reconnectBackoff.length),
        reason: 'un QR périmé ne redeviendra pas valide : on renonce aussitôt',
      );
    });
  });

  test('quitter volontairement → plus aucune reconnexion', () async {
    final (server, info, events) = await startHost();
    final proxy = await _LanProxy.start(info.port);
    final client = WebSocketGuestClient(config: _fastGuest);
    addTearDown(() async {
      await client.dispose();
      await proxy.dispose();
      await server.endSession();
    });

    await client.join(
      session: payloadFor(info, port: proxy.port),
      name: 'Camille',
    );
    await client.leave();
    proxy.cut();
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(client.session, isNull);
    await pumpEventQueue();
    expect(events.whereType<ParticipantJoined>(), hasLength(1));
  });
}
