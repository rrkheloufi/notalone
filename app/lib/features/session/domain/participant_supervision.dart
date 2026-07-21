import 'package:meta/meta.dart';
import 'package:notalone/features/session/domain/participant.dart';
import 'package:notalone/features/session/domain/protocol/session_message.dart';
import 'package:notalone/features/session/domain/supervision_config.dart';

/// Ce que l'hôte doit savoir d'un convive, du plus grave au plus anodin
/// (cf. cowork/01-cadrage-produit.md §7.5).
///
/// Un seul niveau est affiché à la fois : une alerte par convive reste lisible
/// d'un coup d'œil pendant un repas, une liste de symptômes non. L'ordre
/// ci-dessous **est** la priorité — voir [ParticipantSupervision.alert].
enum SupervisionAlert {
  /// Rien à signaler : le micro tourne et la batterie tient.
  none,

  /// La batterie passe sous le seuil. Le micro capte encore : c'est un
  /// avertissement, pas une panne (doc 03 R1).
  lowBattery,

  /// L'invité a coupé son micro lui-même. « Le micro de Paul est coupé » —
  /// l'alerte que l'objectif de MVP-13 cite en exemple.
  muted,

  /// L'OS a repris le micro (appel entrant, autre app) : l'invité n'y peut
  /// rien sur le moment et la reprise est automatique (doc 03 R5).
  interrupted,

  /// Plus de keepalive : le téléphone a quitté le réseau. Rien de ce qu'il dit
  /// n'arrive plus, et lui ne le sait pas.
  disconnected,
}

/// Un convive vu du panneau de supervision : son identité de session, le
/// dernier `mic_status` reçu de lui, et l'alerte qui en découle.
///
/// Pur Dart et immuable : toute la règle de priorité se teste sans écran ni
/// socket. La vue n'a qu'à lire [alert].
@immutable
class ParticipantSupervision {
  const ParticipantSupervision._({
    required this.participant,
    required this.micState,
    required this.batteryPct,
    required this.alert,
  });

  /// Construit l'état d'un convive et **dérive** son alerte. Seule porte
  /// d'entrée : impossible de fabriquer un état dont l'alerte ne correspond
  /// pas au reste.
  factory ParticipantSupervision.from({
    required Participant participant,
    required SupervisionConfig config,
    MicStatusState? micState,
    int? batteryPct,
  }) => ParticipantSupervision._(
    participant: participant,
    micState: micState,
    batteryPct: batteryPct,
    alert: _deriveAlert(
      participant: participant,
      config: config,
      micState: micState,
      batteryPct: batteryPct,
    ),
  );

  final Participant participant;

  /// Nul tant qu'aucun `mic_status` n'est arrivé de ce convive : il vient
  /// d'entrer, ou il tourne sur une version qui n'en émet pas encore. On ne
  /// prétend alors rien savoir de son micro plutôt que de le supposer actif.
  final MicStatusState? micState;

  /// Nul pour la même raison, ou quand la plateforme ne sait pas la lire.
  final int? batteryPct;

  final SupervisionAlert alert;

  String get id => participant.id;

  String get name => participant.name;

  bool get isHost => participant.isHost;

  bool get hasAlert => alert != SupervisionAlert.none;

  /// Priorité, du plus grave au plus anodin. Un convive déconnecté peut être
  /// aussi à 5 % de batterie et micro coupé : ce qui compte est qu'il ne
  /// transmet plus rien, le reste est du détail que l'hôte ne peut pas traiter.
  ///
  /// L'hôte est exclu du cas `disconnected` : il n'a pas de socket vers
  /// lui-même, `isConnected` y est vrai par construction (`registerHost`).
  static SupervisionAlert _deriveAlert({
    required Participant participant,
    required SupervisionConfig config,
    required MicStatusState? micState,
    required int? batteryPct,
  }) {
    if (!participant.isConnected) return SupervisionAlert.disconnected;
    switch (micState) {
      case MicStatusState.interrupted:
        return SupervisionAlert.interrupted;
      case MicStatusState.muted:
        return SupervisionAlert.muted;
      case MicStatusState.active || null:
        break;
    }
    if (batteryPct != null && batteryPct <= config.lowBatteryThresholdPct) {
      return SupervisionAlert.lowBattery;
    }
    return SupervisionAlert.none;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ParticipantSupervision &&
          other.participant == participant &&
          other.micState == micState &&
          other.batteryPct == batteryPct &&
          other.alert == alert);

  @override
  int get hashCode => Object.hash(participant, micState, batteryPct, alert);

  @override
  String toString() =>
      'ParticipantSupervision($name, micro: $micState, '
      'batterie: $batteryPct, alerte: ${alert.name})';
}
