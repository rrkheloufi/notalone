import 'package:meta/meta.dart';

/// Un locuteur tel que le fil a besoin de le connaître : de quoi coiffer une
/// bulle, et rien de plus.
///
/// Volontairement distinct de `Participant` (`session/domain/`), qui porte en
/// plus l'état de connexion et le rôle d'hôte : `transcript/` n'importe jamais
/// `session/` (CLAUDE.md règle 3, précédents `IncomingSegment` et
/// `ClockProbe`). La traduction de l'un vers l'autre vit dans
/// `transcript/data/`.
@immutable
class Speaker {
  const Speaker({
    required this.id,
    required this.name,
    required this.colorIndex,
  });

  /// Le `participantId` que portent les `TranscriptEntry`.
  final String id;

  final String name;

  /// Index dans la palette locuteurs, stable pour toute la session — y compris
  /// après une coupure réseau (cf. `Participant.colorIndex`).
  final int colorIndex;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Speaker &&
          other.id == id &&
          other.name == name &&
          other.colorIndex == colorIndex);

  @override
  int get hashCode => Object.hash(id, name, colorIndex);

  @override
  String toString() => 'Speaker($name, id: $id, couleur: $colorIndex)';
}
