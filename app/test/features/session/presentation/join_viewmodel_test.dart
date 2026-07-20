import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:notalone/core/result/result.dart';
import 'package:notalone/features/session/domain/discovered_session.dart';
import 'package:notalone/features/session/domain/guest_client.dart';
import 'package:notalone/features/session/domain/protocol/session_close_codes.dart';
import 'package:notalone/features/session/domain/protocol/session_message.dart';
import 'package:notalone/features/session/domain/qr_session_payload.dart';
import 'package:notalone/features/session/domain/session_discovery.dart';
import 'package:notalone/features/session/domain/session_failure.dart';
import 'package:notalone/features/session/presentation/join_viewmodel.dart';

const validPayload = QrSessionPayload(
  sessionName: 'Repas',
  host: '192.168.1.10',
  port: 40000,
  token: 'tok',
);

const discovered = DiscoveredSession(
  sessionName: 'Repas de Rayan',
  host: '192.168.1.11',
  port: 40001,
  token: 'tok2',
);

const identity = GuestSession(
  participantId: 'p1',
  colorIndex: 3,
  clockOffsetProbe: 1000,
);

final class _FakeGuestClient implements GuestClient {
  final StreamController<GuestClientEvent> _events =
      StreamController.broadcast();
  final List<SessionMessage> sent = [];

  Result<GuestSession> joinResult = const Result.ok(identity);
  QrSessionPayload? joinedSession;
  String? joinedName;
  int leaveCalls = 0;
  int disposeCalls = 0;

  @override
  Stream<GuestClientEvent> get events => _events.stream;

  @override
  GuestSession? session;

  @override
  Future<Result<GuestSession>> join({
    required QrSessionPayload session,
    required String name,
  }) async {
    joinedSession = session;
    joinedName = name;
    if (joinResult case Ok(value: final joined)) this.session = joined;
    return joinResult;
  }

  @override
  void send(SessionMessage message) => sent.add(message);

  @override
  Future<void> leave() async {
    leaveCalls++;
    session = null;
  }

  @override
  Future<void> dispose() async => disposeCalls++;

  void emit(GuestClientEvent event) => _events.add(event);
}

final class _FakeBrowser implements SessionBrowser {
  final StreamController<List<DiscoveredSession>> _sessions =
      StreamController.broadcast();

  Result<void> startResult = const Result.ok(null);
  int startCalls = 0;
  int stopCalls = 0;

  @override
  Stream<List<DiscoveredSession>> get sessions => _sessions.stream;

  @override
  Future<Result<void>> start() async {
    startCalls++;
    return startResult;
  }

  @override
  Future<void> stop() async => stopCalls++;

  @override
  Future<void> dispose() async {}

  void publish(List<DiscoveredSession> found) => _sessions.add(found);
}

({JoinViewModel viewModel, _FakeGuestClient client, _FakeBrowser browser})
build() {
  final client = _FakeGuestClient();
  final browser = _FakeBrowser();
  return (
    viewModel: JoinViewModel(
      client: client,
      browser: browser,
      initialName: 'Invité',
    ),
    client: client,
    browser: browser,
  );
}

void main() {
  group('scan → prénom → connecté', () {
    test('parcours nominal', () async {
      final (:viewModel, :client, :browser) = build();

      await viewModel.scanCommand.execute(validPayload.encode());
      expect(viewModel.step, JoinStep.confirmingName);
      expect(viewModel.pendingSession, validPayload);
      expect(browser.stopCalls, 1, reason: 'inutile de chercher encore');

      await viewModel.joinCommand.execute('Camille');

      expect(viewModel.step, JoinStep.connected);
      expect(viewModel.name, 'Camille');
      expect(client.joinedSession, validPayload);
      expect(client.joinedName, 'Camille');
      expect(viewModel.session, identity);
    });

    test('le prénom proposé est celui fourni, modifiable', () async {
      final (:viewModel, :client, browser: _) = build();
      expect(viewModel.name, 'Invité');

      await viewModel.scanCommand.execute(validPayload.encode());
      await viewModel.joinCommand.execute('  Camille  ');

      expect(viewModel.name, 'Camille', reason: 'espaces superflus retirés');
      expect(client.joinedName, 'Camille');
    });

    test('prénom vide → on ne tente pas la connexion', () async {
      final (:viewModel, :client, browser: _) = build();
      await viewModel.scanCommand.execute(validPayload.encode());

      await viewModel.joinCommand.execute('   ');

      expect(client.joinedName, isNull);
      expect(viewModel.step, JoinStep.confirmingName);
    });

    test('QR illisible → failure exposée, on reste en scan', () async {
      final (:viewModel, :client, browser: _) = build();

      await viewModel.scanCommand.execute('pas un payload');

      expect(
        viewModel.scanCommand.result?.failureOrNull,
        isA<QrPayloadMalformedFailure>(),
      );
      expect(viewModel.step, JoinStep.scanning);
      expect(client.joinedSession, isNull);
    });

    test(
      'hôte refuse (session pleine) → retour au prénom avec le motif',
      () async {
        final (:viewModel, :client, browser: _) = build();
        client.joinResult = Result.err(
          JoinRefusedFailure(SessionCloseCodes.sessionFull),
        );
        await viewModel.scanCommand.execute(validPayload.encode());

        await viewModel.joinCommand.execute('Camille');

        expect(viewModel.step, JoinStep.confirmingName);
        expect(
          viewModel.joinCommand.result?.failureOrNull,
          isA<JoinRefusedFailure>(),
        );
      },
    );

    test('timeout de connexion (R7) → failure dédiée', () async {
      final (:viewModel, :client, browser: _) = build();
      client.joinResult = const Result.err(ConnectionTimeoutFailure());
      await viewModel.scanCommand.execute(validPayload.encode());

      await viewModel.joinCommand.execute('Camille');

      expect(
        viewModel.joinCommand.result?.failureOrNull,
        isA<ConnectionTimeoutFailure>(),
      );
      expect(viewModel.step, JoinStep.confirmingName);
    });
  });

  group('découverte mDNS (secours du QR)', () {
    test('les sessions trouvées sont exposées', () async {
      final (:viewModel, client: _, :browser) = build();
      await viewModel.discoverCommand.execute();

      browser.publish([discovered]);
      await pumpEventQueue();

      expect(browser.startCalls, 1);
      expect(viewModel.discoveredSessions, [discovered]);
    });

    test(
      'choisir une session trouvée mène au même écran que le scan',
      () async {
        final (:viewModel, :client, browser: _) = build();

        await viewModel.pickCommand.execute(discovered);
        await viewModel.joinCommand.execute('Camille');

        expect(viewModel.step, JoinStep.connected);
        expect(client.joinedSession, discovered.toQrPayload());
        expect(client.joinedSession?.token, 'tok2');
      },
    );

    test('découverte indisponible → le scan reste possible', () async {
      final (:viewModel, client: _, :browser) = build();
      browser.startResult = const Result.err(
        DiscoveryUnavailableFailure('service absent'),
      );

      await viewModel.discoverCommand.execute();

      expect(viewModel.step, JoinStep.scanning);
      expect(
        viewModel.discoverCommand.result?.failureOrNull,
        isA<DiscoveryUnavailableFailure>(),
      );
    });
  });

  group('aléas du réseau', () {
    test('coupure → reconnexion → retour à connecté', () async {
      final (:viewModel, :client, browser: _) = build();
      await viewModel.scanCommand.execute(validPayload.encode());
      await viewModel.joinCommand.execute('Camille');

      client.emit(
        const GuestReconnecting(attempt: 2, delay: Duration(seconds: 2)),
      );
      await pumpEventQueue();
      expect(viewModel.step, JoinStep.reconnecting);
      expect(viewModel.reconnectAttempt, 2);

      client.emit(const GuestReconnected(identity));
      await pumpEventQueue();
      expect(viewModel.step, JoinStep.connected);
      expect(viewModel.reconnectAttempt, 0);
    });

    test('abandon → état terminal avec le motif', () async {
      final (:viewModel, :client, browser: _) = build();
      await viewModel.scanCommand.execute(validPayload.encode());
      await viewModel.joinCommand.execute('Camille');

      client.emit(
        const GuestConnectionLost(ConnectionTimeoutFailure()),
      );
      await pumpEventQueue();

      expect(viewModel.step, JoinStep.lost);
      expect(viewModel.lostReason, isNotNull);
    });

    test('session terminée par l’hôte → état dédié', () async {
      final (:viewModel, :client, browser: _) = build();
      await viewModel.scanCommand.execute(validPayload.encode());
      await viewModel.joinCommand.execute('Camille');

      client.emit(const GuestSessionEnded());
      await pumpEventQueue();

      expect(viewModel.step, JoinStep.ended);
    });

    test('les messages de l’hôte ne perturbent pas cet écran', () async {
      final (:viewModel, :client, browser: _) = build();
      await viewModel.scanCommand.execute(validPayload.encode());
      await viewModel.joinCommand.execute('Camille');

      client.emit(
        const GuestMessageReceived(ClockSync(seq: 1, tHostSentMs: 10)),
      );
      await pumpEventQueue();

      expect(viewModel.step, JoinStep.connected);
    });
  });

  test(
    'rescan → session quittée, recherche relancée, état repartant de zéro',
    () async {
      final (:viewModel, :client, :browser) = build();
      await viewModel.scanCommand.execute(validPayload.encode());
      await viewModel.joinCommand.execute('Camille');
      client.emit(const GuestConnectionLost(ConnectionTimeoutFailure()));
      await pumpEventQueue();

      await viewModel.backToScanning();

      expect(viewModel.step, JoinStep.scanning);
      expect(viewModel.pendingSession, isNull);
      expect(viewModel.lostReason, isNull);
      expect(client.leaveCalls, 1);
      expect(browser.startCalls, 1, reason: 'la recherche reprend');
    },
  );

  test('dispose libère le client et la découverte', () async {
    final (:viewModel, :client, browser: _) = build();

    viewModel.dispose();
    await pumpEventQueue();

    expect(client.disposeCalls, 1);
  });
}
