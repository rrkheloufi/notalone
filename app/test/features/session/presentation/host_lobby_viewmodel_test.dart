import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:notalone/core/result/result.dart';
import 'package:notalone/features/session/domain/host_server.dart';
import 'package:notalone/features/session/domain/participant.dart';
import 'package:notalone/features/session/domain/participant_supervision.dart';
import 'package:notalone/features/session/domain/protocol/session_message.dart';
import 'package:notalone/features/session/domain/qr_session_payload.dart';
import 'package:notalone/features/session/domain/session_discovery.dart';
import 'package:notalone/features/session/domain/session_failure.dart';
import 'package:notalone/features/session/domain/supervise_participants_use_case.dart';
import 'package:notalone/features/session/presentation/host_lobby_viewmodel.dart';

const host = Participant(
  id: 'h1',
  name: 'Rayan',
  colorIndex: 0,
  isHost: true,
  isConnected: true,
);

const guest = Participant(
  id: 'g1',
  name: 'Camille',
  colorIndex: 1,
  isHost: false,
  isConnected: true,
);

final class _FakeHostServer implements HostServer {
  final StreamController<HostServerEvent> _events =
      StreamController.broadcast();
  final List<SessionMessage> broadcasts = [];

  Result<HostServerInfo> startResult = const Result.ok(
    HostServerInfo(
      host: '192.168.1.10',
      port: 40000,
      token: 'tok',
      hostParticipant: host,
    ),
  );
  String? startedWith;
  int endCalls = 0;

  @override
  List<Participant> participants = const [host];

  @override
  Stream<HostServerEvent> get events => _events.stream;

  @override
  Future<Result<HostServerInfo>> start({required String hostName}) async {
    startedWith = hostName;
    return startResult;
  }

  @override
  void broadcast(SessionMessage message) => broadcasts.add(message);

  @override
  void sendTo(String participantId, SessionMessage message) {}

  @override
  Future<void> endSession() async {
    endCalls++;
    participants = const [];
  }

  void emit(HostServerEvent event) => _events.add(event);
}

final class _FakeAdvertiser implements SessionAdvertiser {
  Result<void> advertiseResult = const Result.ok(null);
  String? advertisedName;
  int? advertisedPort;
  String? advertisedToken;
  int stopCalls = 0;

  @override
  Future<Result<void>> advertise({
    required String sessionName,
    required int port,
    required String token,
  }) async {
    advertisedName = sessionName;
    advertisedPort = port;
    advertisedToken = token;
    return advertiseResult;
  }

  @override
  Future<void> stop() async => stopCalls++;
}

({
  HostLobbyViewModel viewModel,
  _FakeHostServer server,
  _FakeAdvertiser advertiser,
})
build() {
  final server = _FakeHostServer();
  final advertiser = _FakeAdvertiser();
  return (
    viewModel: HostLobbyViewModel(
      server: server,
      advertiser: advertiser,
      supervision: SuperviseParticipantsUseCase(server: server),
      hostName: 'Rayan',
      sessionName: 'Conversation de Rayan',
    ),
    server: server,
    advertiser: advertiser,
  );
}

/// Le salon expose désormais des `ParticipantSupervision` (MVP-13) : les
/// assertions d'identité de MVP-06 se lisent à travers cette projection.
List<Participant> supervised(HostLobbyViewModel viewModel) =>
    [for (final entry in viewModel.participants) entry.participant];

void main() {
  group('démarrage', () {
    test('le QR porte le payload complet de la session', () async {
      final (:viewModel, :server, advertiser: _) = build();

      await viewModel.startCommand.execute();

      expect(viewModel.isRunning, isTrue);
      expect(server.startedWith, 'Rayan');
      final payload = QrSessionPayload.decode(viewModel.qrData!).valueOrNull;
      expect(payload, isNotNull);
      expect(payload!.sessionName, 'Conversation de Rayan');
      expect(payload.host, '192.168.1.10');
      expect(payload.port, 40000);
      expect(payload.token, 'tok');
    });

    test('la session est annoncée en mDNS avec son token', () async {
      final (:viewModel, server: _, :advertiser) = build();

      await viewModel.startCommand.execute();

      expect(viewModel.isDiscoverable, isTrue);
      expect(advertiser.advertisedName, 'Conversation de Rayan');
      expect(advertiser.advertisedPort, 40000);
      expect(
        advertiser.advertisedToken,
        'tok',
        reason: 'sans le token, la découverte ne dépannerait personne',
      );
    });

    test('mDNS indisponible → la session tourne quand même', () async {
      final (:viewModel, server: _, :advertiser) = build();
      advertiser.advertiseResult = const Result.err(
        DiscoveryUnavailableFailure('service absent'),
      );

      await viewModel.startCommand.execute();

      expect(viewModel.isRunning, isTrue);
      expect(viewModel.qrData, isNotNull);
      expect(viewModel.isDiscoverable, isFalse);
      expect(viewModel.startCommand.error, isFalse);
    });

    test('WiFi coupé → échec exposé, pas de QR', () async {
      final (:viewModel, :server, advertiser: _) = build();
      server.startResult = const Result.err(
        ServerStartFailure('aucune adresse IPv4 locale'),
      );

      await viewModel.startCommand.execute();

      expect(viewModel.isRunning, isFalse);
      expect(viewModel.qrData, isNull);
      expect(
        viewModel.startCommand.result?.failureOrNull,
        isA<ServerStartFailure>(),
      );
    });
  });

  group('convives', () {
    test('arrivée et départ mettent la liste à jour', () async {
      final (:viewModel, :server, advertiser: _) = build();
      await viewModel.startCommand.execute();
      expect(supervised(viewModel), [host]);

      server
        ..participants = const [host, guest]
        ..emit(
          const ParticipantJoined(participant: guest, isReconnection: false),
        );
      await pumpEventQueue();
      expect(supervised(viewModel), [host, guest]);

      const gone = Participant(
        id: 'g1',
        name: 'Camille',
        colorIndex: 1,
        isHost: false,
        isConnected: false,
      );
      server
        ..participants = const [host, gone]
        ..emit(const ParticipantDisconnected(gone));
      await pumpEventQueue();
      expect(viewModel.participants.last.participant.isConnected, isFalse);
    });

    test('un refus est signalé à l’hôte puis effaçable', () async {
      final (:viewModel, :server, advertiser: _) = build();
      await viewModel.startCommand.execute();

      server.emit(
        const ParticipantRejected(reason: 'session complète', closeCode: 4002),
      );
      await pumpEventQueue();
      expect(viewModel.lastRejection, 'session complète');

      viewModel.clearRejection();
      expect(viewModel.lastRejection, isNull);
    });

    test('les messages applicatifs ne concernent pas le lobby', () async {
      final (:viewModel, :server, advertiser: _) = build();
      await viewModel.startCommand.execute();

      server.emit(
        const SessionMessageReceived(
          participantId: 'g1',
          message: MicStatus(state: MicStatusState.active, batteryPct: 90),
        ),
      );
      await pumpEventQueue();

      expect(supervised(viewModel), [host]);
    });
  });

  group('fin de session', () {
    test('arrête l’annonce, ferme la session et vide l’état', () async {
      final (:viewModel, :server, :advertiser) = build();
      await viewModel.startCommand.execute();

      await viewModel.endSessionCommand.execute();

      expect(viewModel.isEnded, isTrue);
      expect(viewModel.isRunning, isFalse);
      expect(viewModel.isDiscoverable, isFalse);
      expect(viewModel.participants, isEmpty);
      expect(server.endCalls, 1);
      expect(advertiser.stopCalls, greaterThanOrEqualTo(1));
    });

    test('fermer deux fois ne rejoue pas la fin', () async {
      final (:viewModel, :server, advertiser: _) = build();
      await viewModel.startCommand.execute();

      await viewModel.endSessionCommand.execute();
      await viewModel.endSessionCommand.execute();

      expect(server.endCalls, 1);
    });

    test('quitter l’écran sans terminer ferme quand même la session', () async {
      final (:viewModel, :server, advertiser: _) = build();
      await viewModel.startCommand.execute();

      viewModel.dispose();
      await pumpEventQueue();

      expect(
        server.endCalls,
        1,
        reason: 'aucun serveur ne doit survivre à son écran',
      );
    });
  });

  group('supervision (MVP-13)', () {
    test('un mic_status coupé remonte au salon', () async {
      final (:viewModel, :server, advertiser: _) = build();
      await viewModel.startCommand.execute();
      server
        ..participants = const [host, guest]
        ..emit(
          const ParticipantJoined(participant: guest, isReconnection: false),
        );
      await pumpEventQueue();

      server.emit(
        const SessionMessageReceived(
          participantId: 'g1',
          message: MicStatus(state: MicStatusState.muted, batteryPct: 80),
        ),
      );
      await pumpEventQueue();

      expect(viewModel.hasAlerts, isTrue);
      expect(viewModel.alerts.single.name, 'Camille');
      expect(viewModel.alerts.single.alert, SupervisionAlert.muted);
    });

    test('la ligne de l’hôte existe dès le démarrage', () async {
      // `registerHost` n'émet pas d'événement : le salon rappelle la
      // supervision après `start()`, sinon l'hôte ne se verrait pas lui-même.
      final (:viewModel, server: _, advertiser: _) = build();

      await viewModel.startCommand.execute();

      expect(viewModel.participants.map((e) => e.name), ['Rayan']);
      expect(viewModel.hasAlerts, isFalse);
    });

    test('un changement de supervision redessine le salon', () async {
      final (:viewModel, :server, advertiser: _) = build();
      await viewModel.startCommand.execute();
      var notifications = 0;
      viewModel.addListener(() => notifications++);

      server.emit(
        const SessionMessageReceived(
          participantId: 'h1',
          message: MicStatus(state: MicStatusState.muted, batteryPct: 80),
        ),
      );
      await pumpEventQueue();

      expect(notifications, greaterThan(0));
    });

    test('fin de session : plus personne à superviser', () async {
      final (:viewModel, :server, advertiser: _) = build();
      await viewModel.startCommand.execute();
      server
        ..participants = const [host, guest]
        ..emit(
          const ParticipantJoined(participant: guest, isReconnection: false),
        );
      await pumpEventQueue();

      await viewModel.endSessionCommand.execute();
      await pumpEventQueue();

      expect(viewModel.isEnded, isTrue);
      expect(viewModel.participants, isEmpty);
      expect(viewModel.alerts, isEmpty);
    });
  });
}
