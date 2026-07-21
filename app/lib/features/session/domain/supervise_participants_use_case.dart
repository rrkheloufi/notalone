import 'dart:async';

import 'package:meta/meta.dart';
import 'package:notalone/features/session/domain/host_server.dart';
import 'package:notalone/features/session/domain/participant_supervision.dart';
import 'package:notalone/features/session/domain/protocol/session_message.dart';
import 'package:notalone/features/session/domain/supervision_config.dart';

/// Le panneau de supervision de l'hôte, côté métier (cf.
/// cowork/01-cadrage-produit.md §7.5, doc 03 R1 et R5).
///
/// Il croise deux sources et rien d'autre :
/// - le **registre du serveur**, qui dit qui est là et qui est parti (le
///   keepalive de `DartIoHostServer` fait déjà ce travail) ;
/// - les **`mic_status`** que chaque invité pousse, qui disent l'état de son
///   micro et sa batterie.
///
/// Pur Dart : il ne dépend que de l'interface `HostServer`, donc tout le
/// comportement — y compris « micro coupé visible en moins de 10 s » — se
/// rejoue sans ouvrir de socket.
///
/// L'hôte capte sa propre voix comme les autres (doc 02 §1) mais n'a pas de
/// socket vers lui-même : son état passe par [reportLocal] au lieu du réseau.
/// C'est la seule différence entre sa ligne et celle d'un invité.
class SuperviseParticipantsUseCase {
  SuperviseParticipantsUseCase({
    required this._server,
    this._config = const SupervisionConfig(),
  }) {
    _supervised = _read();
    _events = _server.events.listen(_handleEvent);
  }

  final HostServer _server;
  final SupervisionConfig _config;

  late final StreamSubscription<HostServerEvent> _events;

  final StreamController<List<ParticipantSupervision>> _changes =
      StreamController<List<ParticipantSupervision>>.broadcast();

  /// Dernier `mic_status` connu par participant. Séparé du registre parce
  /// qu'il lui survit : un invité qui se reconnecte retrouve son état de micro
  /// sans attendre son prochain envoi.
  final Map<String, _MicHealth> _health = {};

  late List<ParticipantSupervision> _supervised;

  SupervisionConfig get config => _config;

  /// Tous les convives, hôte compris, dans l'ordre du registre.
  List<ParticipantSupervision> get participants =>
      List.unmodifiable(_supervised);

  /// Les seuls qui demandent quelque chose à l'hôte. C'est ce que le bandeau
  /// du fil affiche : le panneau complet reste au salon.
  List<ParticipantSupervision> get alerting => List.unmodifiable(
    _supervised.where((supervised) => supervised.hasAlert),
  );

  bool get hasAlerts => _supervised.any((supervised) => supervised.hasAlert);

  Stream<List<ParticipantSupervision>> get changes => _changes.stream;

  /// Relit le registre. Nécessaire après `HostServer.start()` : l'inscription
  /// de l'hôte (`registerHost`) n'émet aucun événement, sa propre ligne
  /// n'apparaîtrait donc qu'à l'arrivée du premier invité.
  void refresh() => _refresh();

  /// État du micro de l'hôte lui-même, qui ne transite par aucun socket.
  void reportLocal({
    required String participantId,
    required MicStatusState state,
    int? batteryPct,
  }) => _updateHealth(participantId, state, batteryPct);

  /// Fin de session : il ne reste **rien** à superviser. La liste est vidée et
  /// pas seulement figée — après `session_end`, aucun écran ne doit pouvoir
  /// rappeler qui était là ni ce que son micro faisait (critère MVP-13).
  /// L'état est vidé **avant** le démontage des flux, et non après : le
  /// démontage est asynchrone, l'effacement ne doit pas l'attendre. Un écran
  /// qui se redessine entre les deux ne doit jamais pouvoir relire la liste.
  Future<void> dispose() async {
    _health.clear();
    _supervised = const [];
    await _events.cancel();
    await _changes.close();
  }

  void _handleEvent(HostServerEvent event) {
    switch (event) {
      case ParticipantJoined() || ParticipantDisconnected():
        _refresh();
      case SessionMessageReceived(:final participantId, :final message):
        if (message case MicStatus(:final state, :final batteryPct)) {
          _updateHealth(participantId, state, batteryPct);
        }
      case ParticipantRejected():
        // Refusé : il n'est jamais entré dans le registre, il n'y a personne
        // à superviser.
        return;
    }
  }

  void _updateHealth(String participantId, MicStatusState state, int? battery) {
    final health = _MicHealth(state: state, batteryPct: battery);
    if (_health[participantId] == health) return;
    _health[participantId] = health;
    _refresh();
  }

  /// Recalcule et ne notifie **que si quelque chose a bougé** : un `mic_status`
  /// réémis à l'identique toutes les 30 s ne doit pas redessiner le fil du
  /// lecteur pour rien.
  void _refresh() {
    final refreshed = _read();
    if (_listEquals(refreshed, _supervised)) return;
    _supervised = refreshed;
    if (!_changes.isClosed) _changes.add(participants);
  }

  List<ParticipantSupervision> _read() {
    final participants = _server.participants;
    // Un participant oublié du registre (place recyclée) ne doit pas laisser
    // son état de micro derrière lui : la table suit le registre, pas
    // l'inverse.
    final known = {for (final participant in participants) participant.id};
    _health.removeWhere((id, _) => !known.contains(id));
    return [
      for (final participant in participants)
        ParticipantSupervision.from(
          participant: participant,
          config: _config,
          micState: _health[participant.id]?.state,
          batteryPct: _health[participant.id]?.batteryPct,
        ),
    ];
  }

  static bool _listEquals(
    List<ParticipantSupervision> a,
    List<ParticipantSupervision> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Dernier état de micro connu d'un participant. Valeur, pour que la
/// comparaison « rien n'a changé » soit une égalité et non un test champ à
/// champ.
@immutable
class _MicHealth {
  const _MicHealth({required this.state, required this.batteryPct});

  final MicStatusState state;
  final int? batteryPct;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is _MicHealth &&
          other.state == state &&
          other.batteryPct == batteryPct);

  @override
  int get hashCode => Object.hash(state, batteryPct);
}
