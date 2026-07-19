import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:notalone/features/session/data/dart_io_lan_server.dart';
import 'package:notalone/features/session/data/web_socket_lan_client.dart';
import 'package:notalone/features/session/domain/lan_server.dart';
import 'package:notalone/features/session/domain/qr_session_payload.dart';
import 'package:notalone/features/session/domain/session_failure.dart';

QrSessionPayload _payload(int port, String token) => QrSessionPayload(
  sessionName: 'test',
  host: '127.0.0.1',
  port: port,
  token: token,
);

/// Scénario invité exécuté dans un second isolate (conforme à la tâche) :
/// connexion, ping, envoi d'un chat, attente de l'écho de l'hôte.
Future<Map<String, Object?>> _guestScenario((int, String) args) async {
  final (port, token) = args;
  final client = WebSocketLanClient();
  final connected = await client.connect(_payload(port, token));
  if (connected.isErr) return {'error': '${connected.failureOrNull}'};
  final rtt = await client.ping();
  final echo = client.messages.first.timeout(const Duration(seconds: 5));
  client.send('bonjour');
  final received = await echo;
  await client.disconnect();
  return {'rttMicros': rtt.valueOrNull?.inMicroseconds, 'echo': received};
}

/// Isole la closure de `Isolate.run` dans une fonction top-level : elle ne
/// capture ainsi que [port] et [token] (le contexte du test contiendrait le
/// serveur, non sérialisable entre isolates).
Future<Map<String, Object?>> _runGuestIsolate(int port, String token) =>
    Isolate.run(() => _guestScenario((port, token)));

void main() {
  test(
    'hôte + invité dans 2 isolates : connexion, ping, chat, écho, départ',
    () async {
      final server = DartIoLanServer();
      final events = <LanServerEvent>[];
      final left = server.events
          .firstWhere((event) => event is LanClientDisconnected)
          .timeout(const Duration(seconds: 5));
      final subscription = server.events.listen((event) {
        events.add(event);
        if (event is LanMessageReceived) server.broadcast('écho ${event.text}');
      });
      final info = (await server.start()).valueOrNull;
      expect(info, isNotNull, reason: 'serveur démarré');
      final port = info!.port;
      final token = info.token;

      final result = await _runGuestIsolate(port, token);

      expect(result['error'], isNull);
      expect(result['echo'], 'écho bonjour');
      expect(result['rttMicros'], isNotNull);
      await left; // la déconnexion de l'invité est vue côté hôte
      expect(events.whereType<LanClientConnected>(), hasLength(1));
      expect(events.whereType<LanMessageReceived>().single.text, 'bonjour');
      await subscription.cancel();
      await server.stop();
    },
  );

  test(
    'mauvais token → refus franc (ConnectionFailure, pas un timeout)',
    () async {
      final server = DartIoLanServer();
      final info = (await server.start()).valueOrNull!;
      final client = WebSocketLanClient();

      final result = await client.connect(_payload(info.port, 'mauvais-token'));

      expect(result.failureOrNull, isA<ConnectionFailure>());
      expect(result.failureOrNull, isNot(isA<ConnectionTimeoutFailure>()));
      await server.stop();
    },
  );

  test('serveur muet → ConnectionTimeoutFailure (R7 : WiFi isolant)', () async {
    // Accepte le TCP mais ne répond jamais à l'upgrade WebSocket : même
    // symptôme qu'un AP qui isole les clients.
    final silent = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final accepted = <Socket>[];
    final subscription = silent.listen(accepted.add);
    final client = WebSocketLanClient(
      connectTimeout: const Duration(milliseconds: 300),
    );

    final result = await client.connect(_payload(silent.port, 'x'));

    expect(result.failureOrNull, isA<ConnectionTimeoutFailure>());
    for (final socket in accepted) {
      socket.destroy();
    }
    await subscription.cancel();
    await silent.close();
  });

  test(
    'le chat d un invité est relayé aux autres invités, pas à lui-même',
    () async {
      final server = DartIoLanServer();
      final info = (await server.start()).valueOrNull!;
      final alice = WebSocketLanClient();
      final bob = WebSocketLanClient();
      expect(
        (await alice.connect(_payload(info.port, info.token))).isOk,
        isTrue,
      );
      expect((await bob.connect(_payload(info.port, info.token))).isOk, isTrue);
      final aliceInbox = <String>[];
      final aliceSubscription = alice.messages.listen(aliceInbox.add);
      final bobFirst = bob.messages.first.timeout(const Duration(seconds: 5));

      alice.send('salut');

      expect(await bobFirst, 'salut');
      await pumpEventQueue();
      expect(aliceInbox, isEmpty, reason: 'pas d écho à l émetteur');
      await aliceSubscription.cancel();
      await alice.disconnect();
      await bob.disconnect();
      await server.stop();
    },
  );
}
