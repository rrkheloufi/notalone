import 'package:meta/meta.dart';

/// Seuils du pipeline de détection de parole (cf. cowork/02-architecture.md
/// §1). Valeurs par défaut du spike MVP-02, à calibrer sur données réelles
/// en MVP-15 — jamais de seuil en dur dans la logique (conventions.md).
@immutable
class VadConfig {
  const VadConfig({
    this.sampleRate = 16000,
    this.frameSize = 512,
    this.speechStartProbability = 0.5,
    this.speechEndProbability = 0.35,
    this.minSpeechMs = 200,
    this.minSilenceMs = 600,
    this.preRollMs = 200,
    this.maxSegmentMs = 15000,
    this.minSegmentEnergyDbfs = -45,
  });

  /// 16 kHz : fréquence d'entraînement de Silero VAD.
  final int sampleRate;

  /// 512 samples = 32 ms à 16 kHz : taille de frame attendue par Silero v5.
  final int frameSize;

  /// Hystérésis : au-dessus → la parole commence…
  final double speechStartProbability;

  /// …et elle ne s'arrête qu'en dessous (évite le clignotement au seuil).
  final double speechEndProbability;

  /// Parole cumulée minimale avant de confirmer un début de segment.
  /// 200 ms pour tenir le critère « retard de détection < 300 ms » (MVP-02).
  final int minSpeechMs;

  /// Silence continu minimal avant de clore un segment : une micro-pause
  /// plus courte reste dans le même segment.
  final int minSilenceMs;

  /// Audio conservé **avant** le franchissement du seuil VAD et joint au
  /// segment : le détecteur confirme la parole une fois la première syllabe
  /// déjà commencée, sans ce rattrapage le STT (MVP-10) reçoit une attaque
  /// rognée.
  final int preRollMs;

  /// Durée maximale d'un segment : au-delà, il est coupé et la parole
  /// enchaîne sur un nouveau segment. Borne à la fois la latence perçue et
  /// la mémoire du buffer audio (15 s ≈ 960 Ko en float 16 kHz).
  final int maxSegmentMs;

  /// Plancher de bruit : un segment moins énergique est abandonné sans être
  /// transcrit. MVP-02 a mesuré la voix du porteur entre −39 dBFS (téléphone
  /// à 1,5 m) et −14 dBFS (à 30 cm) : à −45 dBFS on ne rejette donc que ce
  /// qui est plus faible qu'une voix à bout de table. Ce seuil n'arbitre
  /// **pas** la proximité — c'est le métier de la déduplication (MVP-11).
  /// À recalibrer sur données réelles en MVP-15.
  final double minSegmentEnergyDbfs;

  int get minSpeechSamples => minSpeechMs * sampleRate ~/ 1000;

  int get minSilenceSamples => minSilenceMs * sampleRate ~/ 1000;

  int get preRollSamples => preRollMs * sampleRate ~/ 1000;

  int get maxSegmentSamples => maxSegmentMs * sampleRate ~/ 1000;
}
