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

  int get minSpeechSamples => minSpeechMs * sampleRate ~/ 1000;

  int get minSilenceSamples => minSilenceMs * sampleRate ~/ 1000;
}
