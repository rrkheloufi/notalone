import 'dart:math';

import 'package:notalone/core/result/result.dart';
import 'package:notalone/features/session/domain/participant.dart';
import 'package:notalone/features/session/domain/session_config.dart';
import 'package:notalone/features/session/domain/session_failure.dart';

/// Identifiants opaques de 128 bits (`Random.secure`) : ils circulent dans le
/// protocole et servent de jeton de reprise, ils doivent donc être non
/// devinables. Injectable pour rendre les tests déterministes.
String generateParticipantId() {
  final random = Random.secure();
  return [
    for (var i = 0; i < 16; i++)
      random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ].join();
}

/// Registre des participants d'une session hôte : attribution des identités
/// et des couleurs, admission (limite du [SessionConfig]), déconnexion et
/// reprise. Pur Dart, sans transport ni horloge — le serveur (`data/`) s'y
/// adosse mais toute la règle métier vit ici (cf. cowork/02-architecture.md
/// §6).
class ParticipantRegistry {
  ParticipantRegistry({
    this.config = const SessionConfig(),
    this.generateId = generateParticipantId,
  });

  final SessionConfig config;
  final String Function() generateId;

  final Map<String, Participant> _byId = {};

  /// Ordre de déconnexion : la place d'un participant parti depuis le plus
  /// longtemps est recyclée en premier quand la palette est saturée. Un
  /// compteur, pas une horloge, pour rester pur et déterministe.
  final Map<String, int> _disconnectOrder = {};
  int _disconnectSeq = 0;

  List<Participant> get participants => List.unmodifiable(_byId.values);

  List<Participant> get connected =>
      List.unmodifiable(_byId.values.where((p) => p.isConnected));

  Participant? byId(String id) => _byId[id];

  /// Inscrit l'hôte, qui capte sa propre voix comme les autres (doc 02 §1) :
  /// il occupe une place et la première couleur, sans socket.
  Participant registerHost(String name) {
    final host = Participant(
      id: generateId(),
      name: name,
      colorIndex: _takeColorIndex(),
      isHost: true,
      isConnected: true,
    );
    _byId[host.id] = host;
    return host;
  }

  /// Admet un invité. [participantId] non nul et connu = reconnexion : le
  /// participant retrouve son identité et sa couleur, et son prénom est
  /// rafraîchi s'il l'a changé entre-temps. Un identifiant inconnu (session
  /// redémarrée, autre hôte) est traité comme un premier join plutôt que
  /// rejeté : l'invité n'a rien à faire de plus que rescanner le QR.
  ///
  /// Une reconnexion sur un participant encore marqué connecté est acceptée
  /// et remplace la connexion précédente : le cas nominal d'un WiFi qui
  /// tombe est que l'invité revienne **avant** que le keepalive (jusqu'à 15 s)
  /// n'ait constaté son départ — le rejeter l'enfermerait dehors. C'est sans
  /// risque d'usurpation, l'identifiant étant un secret de 128 bits.
  Result<Participant> join({required String name, String? participantId}) {
    final known = participantId == null ? null : _byId[participantId];
    if (known != null) {
      final rejoined = known.copyWith(name: name, isConnected: true);
      _byId[known.id] = rejoined;
      _disconnectOrder.remove(known.id);
      return Result.ok(rejoined);
    }
    if (connected.length >= config.maxParticipants) {
      return Result.err(SessionFullFailure(config.maxParticipants));
    }
    final guest = Participant(
      id: generateId(),
      name: name,
      colorIndex: _takeColorIndex(),
      isHost: false,
      isConnected: true,
    );
    _byId[guest.id] = guest;
    return Result.ok(guest);
  }

  /// Marque le participant déconnecté sans l'oublier : son identité et sa
  /// couleur lui restent réservées pour une reconnexion.
  Participant? markDisconnected(String id) {
    final participant = _byId[id];
    if (participant == null || !participant.isConnected) return null;
    final disconnected = participant.copyWith(isConnected: false);
    _byId[id] = disconnected;
    _disconnectOrder[id] = _disconnectSeq++;
    return disconnected;
  }

  /// Fin de session : plus aucune trace des participants côté hôte
  /// (transcript et session éphémères, CLAUDE.md règle 5).
  void clear() {
    _byId.clear();
    _disconnectOrder.clear();
    _disconnectSeq = 0;
  }

  /// Plus petit index de couleur libre. Si toute la palette est réservée mais
  /// qu'une place est disponible, elle l'est forcément par un participant
  /// déconnecté : on recycle celle du plus ancien parti, qui perd alors sa
  /// réservation (il reviendrait comme un nouvel invité).
  int _takeColorIndex() {
    final taken = {for (final p in _byId.values) p.colorIndex};
    for (var index = 0; index < config.maxParticipants; index++) {
      if (!taken.contains(index)) return index;
    }
    final oldest = _oldestDisconnectedId();
    if (oldest == null) {
      // Inatteignable : l'appelant vérifie la capacité avant d'attribuer.
      throw StateError('registre plein, aucune couleur à recycler');
    }
    final recycled = _byId.remove(oldest)!;
    _disconnectOrder.remove(oldest);
    return recycled.colorIndex;
  }

  String? _oldestDisconnectedId() {
    String? oldest;
    var oldestSeq = -1;
    for (final entry in _disconnectOrder.entries) {
      if (oldest == null || entry.value < oldestSeq) {
        oldest = entry.key;
        oldestSeq = entry.value;
      }
    }
    return oldest;
  }
}
