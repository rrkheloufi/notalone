import 'package:flutter_test/flutter_test.dart';
import 'package:notalone/features/session/domain/participant.dart';
import 'package:notalone/features/session/domain/participant_supervision.dart';
import 'package:notalone/features/session/domain/protocol/session_message.dart';
import 'package:notalone/features/session/domain/supervision_config.dart';

const config = SupervisionConfig();

Participant participant({bool isConnected = true, bool isHost = false}) =>
    Participant(
      id: 'g1',
      name: 'Paul',
      colorIndex: 1,
      isHost: isHost,
      isConnected: isConnected,
    );

SupervisionAlert alertOf({
  MicStatusState? micState,
  int? batteryPct,
  bool isConnected = true,
  bool isHost = false,
}) => ParticipantSupervision.from(
  participant: participant(isConnected: isConnected, isHost: isHost),
  config: config,
  micState: micState,
  batteryPct: batteryPct,
).alert;

void main() {
  group('alerte dérivée de l’état', () {
    test('micro actif et batterie pleine → rien à signaler', () {
      expect(
        alertOf(micState: MicStatusState.active, batteryPct: 80),
        SupervisionAlert.none,
      );
    });

    test('micro coupé par l’invité → « le micro de Paul est coupé »', () {
      expect(
        alertOf(micState: MicStatusState.muted, batteryPct: 80),
        SupervisionAlert.muted,
      );
    });

    test('micro repris par l’OS → interrompu (doc 03 R5)', () {
      expect(
        alertOf(micState: MicStatusState.interrupted, batteryPct: 80),
        SupervisionAlert.interrupted,
      );
    });

    test('sous le seuil de batterie → alerte batterie (doc 03 R1)', () {
      expect(
        alertOf(
          micState: MicStatusState.active,
          batteryPct: config.lowBatteryThresholdPct,
        ),
        SupervisionAlert.lowBattery,
      );
      expect(
        alertOf(
          micState: MicStatusState.active,
          batteryPct: config.lowBatteryThresholdPct + 1,
        ),
        SupervisionAlert.none,
      );
    });
  });

  group('priorité : une seule alerte par convive', () {
    test('déconnecté prime sur tout le reste', () {
      // Il ne transmet plus rien : sa batterie et son micro sont du détail que
      // l'hôte ne peut de toute façon pas traiter.
      expect(
        alertOf(
          micState: MicStatusState.muted,
          batteryPct: 3,
          isConnected: false,
        ),
        SupervisionAlert.disconnected,
      );
    });

    test('un micro en défaut prime sur la batterie faible', () {
      // Le micro coupé fait perdre du texte tout de suite ; la batterie
      // annonce une panne à venir.
      expect(
        alertOf(micState: MicStatusState.muted, batteryPct: 5),
        SupervisionAlert.muted,
      );
      expect(
        alertOf(micState: MicStatusState.interrupted, batteryPct: 5),
        SupervisionAlert.interrupted,
      );
    });
  });

  group('ce qu’on ne sait pas encore', () {
    test('aucun mic_status reçu → aucune alerte, mais aucune promesse', () {
      final supervised = ParticipantSupervision.from(
        participant: participant(),
        config: config,
      );

      expect(supervised.micState, isNull);
      expect(supervised.batteryPct, isNull);
      expect(supervised.alert, SupervisionAlert.none);
    });

    test('batterie inconnue → jamais d’alerte batterie', () {
      // « Je ne sais pas » ne doit pas se lire « batterie vide » : un zéro par
      // défaut aurait affolé le panneau sans raison (cf. MicStatus.batteryPct).
      expect(
        alertOf(micState: MicStatusState.active),
        SupervisionAlert.none,
      );
    });
  });

  test('l’hôte n’est jamais « déconnecté » de lui-même', () {
    // `registerHost` le marque connecté par construction : il n'a pas de socket
    // vers lui-même, l'alerte n'aurait aucun sens.
    expect(
      alertOf(micState: MicStatusState.active, isHost: true),
      SupervisionAlert.none,
    );
  });

  test('égalité par valeur, alerte comprise', () {
    final a = ParticipantSupervision.from(
      participant: participant(),
      config: config,
      micState: MicStatusState.active,
      batteryPct: 50,
    );
    final same = ParticipantSupervision.from(
      participant: participant(),
      config: config,
      micState: MicStatusState.active,
      batteryPct: 50,
    );
    final other = ParticipantSupervision.from(
      participant: participant(),
      config: config,
      micState: MicStatusState.muted,
      batteryPct: 50,
    );

    expect(a, same);
    expect(a.hashCode, same.hashCode);
    expect(a, isNot(other));
    expect(a.toString(), contains('Paul'));
    expect(a.toString(), contains('none'));
  });
}
