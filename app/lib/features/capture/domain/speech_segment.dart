import 'dart:math';
import 'dart:typed_data';

import 'package:meta/meta.dart';

/// Identifiant opaque de segment. Contrairement au `participantId`, il ne sert
/// pas de jeton : il ne fait qu'appairer un segment et sa transcription au
/// travers du protocole. 64 bits suffisent à éviter les collisions entre les
/// quelques milliers de segments d'un repas.
String generateSegmentId() {
  final random = Random();
  return [
    for (var i = 0; i < 8; i++)
      random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ].join();
}

/// Une prise de parole détectée sur ce téléphone, prête pour le STT.
///
/// [samples] ne quitte jamais l'appareil et n'est jamais écrit sur disque
/// (CLAUDE.md règle 2) : le buffer vit en mémoire le temps que le moteur STT
/// (MVP-10) le consomme, puis disparaît avec le segment. Seuls le texte et
/// les métadonnées partent ensuite sur le fil.
@immutable
class SpeechSegment {
  const SpeechSegment({
    required this.segmentId,
    required this.tStartMs,
    required this.tEndMs,
    required this.energyDbfs,
    required this.samples,
    required this.sampleRate,
  });

  final String segmentId;

  /// Horodatages **epoch** : l'hôte les corrigera de l'offset d'horloge de cet
  /// invité (MVP-09) avant de fusionner (cf. cowork/02-architecture.md §5).
  final int tStartMs;

  final int tEndMs;

  /// Énergie RMS en dBFS de la partie parlée, sur laquelle la déduplication
  /// cross-talk arbitrera qui était le plus près (doc 02 §5).
  final double energyDbfs;

  /// PCM float mono [-1;1], pré-roll compris.
  final Float32List samples;

  final int sampleRate;

  int get durationMs => tEndMs - tStartMs;
}
