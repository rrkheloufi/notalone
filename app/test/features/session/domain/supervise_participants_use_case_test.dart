import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:notalone/core/result/result.dart';
import 'package:notalone/features/session/domain/host_server.dart';
import 'package:notalone/features/session/domain/participant.dart';
import 'package:notalone/features/session/domain/participant_supervision.dart';
import 'package:notalone/features/session/domain/protocol/session_message.dart';
import 'package:notalone/features/session/domain/supervise_participants_use_case.dart';
import 'package:notalone/features/session/domain/supervision_config.dart';

const host = Participant(
  id: 'h1',
  name: 'Rayan',
  colorIndex: 0,
  isHost: true,
  isConnected: true,
);

const paul = Participant(
  id: 'g1',
  name: 'Paul',
  colorIndex: 1,
  isHost: false,
  isConnected: true,
);

const paulGone = Participant(
  id: 'g1',
  name: 'Paul',
  colorIndex: 1,
  isHost: false,
  isConnected: false,
);

final class _FakeHostServer implements HostServer {
  final StreamController<HostServerEvent> _events =
      StreamController.broadcast();

  @override
  List<Participant> participants = const [host];

  @override
  Stream<HostServerEvent> get events => _events.stream;

  @override
  Future<Result<HostServerInfo>> start({required String hostName}) async =>
      const Result.ok(
        HostServerInfo(
          host: '192.168.1.10',
          port: 40000,
          token: 'tok',
          hostParticipant: host,
        ),
      );

  @override
  void broadcast(SessionMessage message) {}

  @override
  void sendTo(String participantId, SessionMessage message) {}

  @override
  Future<void> endSession() async => participants = const [];

  void emit(HostServerEvent event) => _events.add(event);

  /// Un `mic_status` tel que le serveur le remonte au reste de l'app.
  void micStatus(String participantId, MicStatusState state, {int? battery}) =>
      emit(
        SessionMessageReceived(
          participantId: participantId,
          message: MicStatus(state: state, batteryPct: battery),
        ),
      );

  void join(Participant participant) {
    participants = [...participants, participant];
    emit(ParticipantJoined(participant: participant, isReconnection: false));
  }
}

ParticipantSupervision entryFor(
  SuperviseParticipantsUseCase supervision,
  String id,
) => supervision.participants.firstWhere((entry) => entry.id == id);

void main() {
  late _FakeHostServer server;
  late SuperviseParticipantsUseCase supervision;

  setUp(() {
    server = _FakeHostServer();
    supervision = SuperviseParticipantsUseCase(server: server);
  });

  tearDown(() => supervision.dispose());

  group('le registre peuple le panneau', () {
    test('l’hôte apparaît dès le rappel qui suit le démarrage', () {
      // `registerHost` n'émet aucun événement : sans `refresh`, la ligne de
      // l'hôte n'apparaîtrait qu'à l'arrivée du premier invité.
      supervision.refresh();

      expect(supervision.participants.map((e) => e.name), ['Rayan']);
    });

    test('un invité qui entre apparaît, un qui part reste signalé', () async {
      server.join(paul);
      await pumpEventQueue();
      expect(supervision.participants, hasLength(2));

      server
        ..participants = const [host, paulGone]
        ..emit(const ParticipantDisconnected(paulGone));
      await pumpEventQueue();

      expect(
        entryFor(supervision, 'g1').alert,
        SupervisionAlert.disconnected,
        reason: 'ses phrases sont déjà au fil : il ne disparaît pas du panneau',
      );
    });

    test('un refus ne fait entrer personne', () async {
      server.emit(
        const ParticipantRejected(reason: 'session complète', closeCode: 4002),
      );
      await pumpEventQueue();

      expect(supervision.participants, hasLength(1));
    });
  });

  group('mic_status bout en bout (client simulé)', () {
    test('un micro coupé remonte jusqu’au panneau', () async {
      server
        ..join(paul)
        ..micStatus('g1', MicStatusState.muted, battery: 90);
      await pumpEventQueue();

      final paulEntry = entryFor(supervision, 'g1');
      expect(paulEntry.micState, MicStatusState.muted);
      expect(paulEntry.batteryPct, 90);
      expect(paulEntry.alert, SupervisionAlert.muted);
      expect(supervision.hasAlerts, isTrue);
      expect(supervision.alerting.map((e) => e.id), ['g1']);
    });

    test('le micro qui repart efface l’alerte', () async {
      server
        ..join(paul)
        ..micStatus('g1', MicStatusState.muted, battery: 90);
      await pumpEventQueue();
      server.micStatus('g1', MicStatusState.active, battery: 90);
      await pumpEventQueue();

      expect(entryFor(supervision, 'g1').alert, SupervisionAlert.none);
      expect(supervision.hasAlerts, isFalse);
    });

    test('batterie sous le seuil → alerte, micro actif compris', () async {
      server
        ..join(paul)
        ..micStatus('g1', MicStatusState.active, battery: 12);
      await pumpEventQueue();

      expect(entryFor(supervision, 'g1').alert, SupervisionAlert.lowBattery);
    });

    test('le seuil de batterie est celui de la config', () async {
      final strict = SuperviseParticipantsUseCase(
        server: server,
        config: const SupervisionConfig(lowBatteryThresholdPct: 50),
      );
      addTearDown(strict.dispose);

      server
        ..join(paul)
        ..micStatus('g1', MicStatusState.active, battery: 40);
      await pumpEventQueue();

      expect(entryFor(strict, 'g1').alert, SupervisionAlert.lowBattery);
      expect(
        entryFor(supervision, 'g1').alert,
        SupervisionAlert.none,
        reason: 'le seuil par défaut, lui, laisse passer 40 %',
      );
    });

    test('un mic_status d’un inconnu ne crée pas de ligne', () async {
      server.micStatus('fantôme', MicStatusState.muted);
      await pumpEventQueue();

      expect(
        supervision.participants.map((e) => e.id),
        isNot(contains('fantôme')),
      );
    });
  });

  group('notifications', () {
    test('un changement d’état est diffusé', () async {
      final seen = <List<ParticipantSupervision>>[];
      supervision.changes.listen(seen.add);
      server.join(paul);
      await pumpEventQueue();
      seen.clear();

      server.micStatus('g1', MicStatusState.muted);
      await pumpEventQueue();

      expect(seen, hasLength(1));
    });

    test('un mic_status réémis à l’identique ne diffuse rien', () async {
      // Le rapporteur réémet toutes les 30 s : redessiner le fil du lecteur à
      // chaque fois, pour rien, serait le pire des comportements sur l'écran
      // qu'il est en train de lire.
      final seen = <List<ParticipantSupervision>>[];
      supervision.changes.listen(seen.add);
      server
        ..join(paul)
        ..micStatus('g1', MicStatusState.active, battery: 80);
      await pumpEventQueue();
      seen.clear();

      server.micStatus('g1', MicStatusState.active, battery: 80);
      await pumpEventQueue();

      expect(seen, isEmpty);
    });
  });

  group('l’hôte, qui n’a pas de socket vers lui-même', () {
    test('son état passe par reportLocal', () async {
      supervision
        ..refresh()
        ..reportLocal(
          participantId: 'h1',
          state: MicStatusState.muted,
          batteryPct: 70,
        );

      final hostEntry = entryFor(supervision, 'h1');
      expect(hostEntry.alert, SupervisionAlert.muted);
      expect(hostEntry.batteryPct, 70);
    });
  });

  test('fin de session : il ne reste rien à superviser', () async {
    server
      ..join(paul)
      ..micStatus('g1', MicStatusState.muted, battery: 10);
    await pumpEventQueue();
    expect(supervision.participants, isNotEmpty);

    await supervision.dispose();

    // Aucun écran redessiné entre-temps ne doit pouvoir rappeler qui était là
    // (critère « aucune trace », MVP-13).
    expect(supervision.participants, isEmpty);
    expect(supervision.alerting, isEmpty);
    expect(supervision.hasAlerts, isFalse);
  });
}
