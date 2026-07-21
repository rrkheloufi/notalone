import 'package:meta/meta.dart';

/// Un `speech_segment` tel qu'il entre dans la fusion, quel qu'en soit
/// l'émetteur — un invité par le fil, ou l'hôte qui capte sa propre voix
/// (doc 02 §1).
///
/// Volontairement distinct du DTO `SpeechSegmentDto` : `transcript/` ne dépend
/// pas du protocole de `session/` (CLAUDE.md règle 3, précédent MVP-09 où
/// `ClockProbe` s'exprime en nombres et non en `ClockSync`). Le mapping se
/// fait dans `transcript/data/`.
@immutable
class IncomingSegment {
  const IncomingSegment({
    required this.participantId,
    required this.segmentId,
    required this.tStartMs,
    required this.tEndMs,
    required this.text,
    required this.energyDb,
    required this.engine,
    this.isFinal = true,
  });

  /// Qui a parlé. C'est aussi la clé de correction d'horloge : chaque
  /// participant a son offset.
  final String participantId;

  final String segmentId;

  /// Horodatages sur l'horloge de **l'émetteur** — la fusion les ramènera sur
  /// celle de l'hôte (doc 02 §5.1).
  final int tStartMs;

  final int tEndMs;

  final String text;

  /// Énergie RMS de la partie parlée, en dBFS : c'est elle qui désigne le
  /// vainqueur quand deux micros ont capté la même phrase (doc 02 §5.3).
  final double energyDb;

  final String engine;

  /// Les partiels ne participent pas à la déduplication (doc 02 §5.4) ; la
  /// fusion les écarte avec un compteur tant qu'aucun moteur n'en produit
  /// (décidé avec Rayan le 21/07/2026, cf. MVP-14).
  final bool isFinal;

  int get durationMs => tEndMs - tStartMs;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is IncomingSegment &&
          other.participantId == participantId &&
          other.segmentId == segmentId &&
          other.tStartMs == tStartMs &&
          other.tEndMs == tEndMs &&
          other.text == text &&
          other.energyDb == energyDb &&
          other.engine == engine &&
          other.isFinal == isFinal);

  @override
  int get hashCode => Object.hash(
    participantId,
    segmentId,
    tStartMs,
    tEndMs,
    text,
    energyDb,
    engine,
    isFinal,
  );
}
