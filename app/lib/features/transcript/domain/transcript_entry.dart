import 'package:meta/meta.dart';

/// Une prise de parole telle qu'elle entre dans le fil du lecteur : attribuée,
/// datée sur l'horloge de l'hôte, débarrassée de ses doublons.
///
/// Ne porte **ni prénom ni couleur** : seulement le [participantId]. La
/// jointure avec le registre des participants est le métier de l'écran
/// (MVP-12) ; l'y faire ici obligerait `transcript/domain/` à connaître
/// `session/` (CLAUDE.md règle 3, précédent MVP-09).
@immutable
class TranscriptEntry {
  const TranscriptEntry({
    required this.segmentId,
    required this.participantId,
    required this.text,
    required this.tStartMs,
    required this.tEndMs,
    required this.energyDb,
    required this.engine,
    this.isLate = false,
    this.mergedSegmentIds = const [],
  });

  /// Celui du segment retenu — le plus énergique quand plusieurs micros ont
  /// capté la même phrase.
  final String segmentId;

  final String participantId;

  final String text;

  /// Horodatages ramenés sur l'**horloge de l'hôte** (doc 02 §5.1) : c'est la
  /// seule sur laquelle le fil est ordonné.
  final int tStartMs;

  final int tEndMs;

  final double energyDb;

  final String engine;

  /// L'entrée est sortie après que du texte plus récent a été figé : elle
  /// s'affiche hors de sa place chronologique plutôt que d'être perdue
  /// (décision MVP-09 — le lecteur est sourd, ce fil est tout ce qu'il a).
  final bool isLate;

  /// Segments d'autres convives reconnus comme le même énoncé et écartés.
  /// Conservés pour objectiver le taux de doublons en MVP-15, et pour qu'un
  /// diagnostic puisse dire *pourquoi* une phrase manque quelque part.
  final List<String> mergedSegmentIds;

  int get durationMs => tEndMs - tStartMs;

  /// Nombre de micros supplémentaires ayant capté le même énoncé.
  int get duplicateCount => mergedSegmentIds.length;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TranscriptEntry &&
          other.segmentId == segmentId &&
          other.participantId == participantId &&
          other.text == text &&
          other.tStartMs == tStartMs &&
          other.tEndMs == tEndMs &&
          other.energyDb == energyDb &&
          other.engine == engine &&
          other.isLate == isLate &&
          _sameIds(other.mergedSegmentIds, mergedSegmentIds));

  @override
  int get hashCode => Object.hash(
    segmentId,
    participantId,
    text,
    tStartMs,
    tEndMs,
    energyDb,
    engine,
    isLate,
    Object.hashAll(mergedSegmentIds),
  );

  @override
  String toString() =>
      'TranscriptEntry($participantId @$tStartMs, "$text"'
      '${duplicateCount > 0 ? ', +$duplicateCount doublon(s)' : ''}'
      '${isLate ? ', tardive' : ''})';

  static bool _sameIds(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
