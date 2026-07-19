import 'package:meta/meta.dart';

/// Convive d'une session. L'[id] est opaque et aléatoire (128 bits) : il
/// identifie l'émetteur des `speech_segment` et sert de jeton de reprise à la
/// reconnexion (cf. `JoinRequest.participantId`). Le [colorIndex] indexe la
/// palette locuteurs et reste stable tant que le participant est connu de la
/// session, y compris après une coupure réseau.
@immutable
class Participant {
  const Participant({
    required this.id,
    required this.name,
    required this.colorIndex,
    required this.isHost,
    required this.isConnected,
  });

  final String id;
  final String name;
  final int colorIndex;
  final bool isHost;
  final bool isConnected;

  Participant copyWith({String? name, bool? isConnected}) => Participant(
    id: id,
    name: name ?? this.name,
    colorIndex: colorIndex,
    isHost: isHost,
    isConnected: isConnected ?? this.isConnected,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Participant &&
          other.id == id &&
          other.name == name &&
          other.colorIndex == colorIndex &&
          other.isHost == isHost &&
          other.isConnected == isConnected);

  @override
  int get hashCode => Object.hash(id, name, colorIndex, isHost, isConnected);

  @override
  String toString() =>
      'Participant($name, id: $id, couleur: $colorIndex, '
      'hôte: $isHost, connecté: $isConnected)';
}
