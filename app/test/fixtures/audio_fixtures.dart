import 'dart:typed_data';

import 'package:notalone/features/capture/domain/vad_config.dart';

/// Buffers synthétiques du pipeline de capture. Une frame porte une amplitude
/// constante : l'énergie RMS en dBFS vaut alors exactement 20·log₁₀(amplitude),
/// ce qui rend les seuils vérifiables à la main.
///
/// | amplitude | énergie   | ce que ça représente             |
/// |-----------|-----------|----------------------------------|
/// | 0,5       | −6 dBFS   | voix à 30 cm (MVP-02 : −14 dBFS) |
/// | 0,02      | −34 dBFS  | voix à 1,5 m (MVP-02 : −39 dBFS) |
/// | 0,002     | −54 dBFS  | bruit de salle, sous le plancher |
abstract final class AudioFixtures {
  static const config = VadConfig();

  /// Voix proche, franchement au-dessus du filtre énergie.
  static const double loudVoice = 0.5;

  /// Voix lointaine mais transcriptible : doit passer le filtre.
  static const double distantVoice = 0.02;

  /// Bruit de fond : doit être écarté par le filtre énergie.
  static const double roomNoise = 0.002;

  static const double silent = 0;

  /// Probabilités VAD franches, loin des seuils d'hystérésis.
  static const double speech = 0.9;
  static const double noSpeech = 0.01;

  static Float32List frame(double amplitude) =>
      Float32List(config.frameSize)..fillRange(0, config.frameSize, amplitude);

  /// Une prise de parole complète : [frames] frames parlées puis assez de
  /// silence pour que le segmenteur clôture (minSilenceMs).
  static List<(Float32List, double)> utterance({
    double amplitude = loudVoice,
    int frames = 10,
  }) => [
    for (var i = 0; i < frames; i++) (frame(amplitude), speech),
    ...closingSilence(),
  ];

  static List<(Float32List, double)> closingSilence() {
    final needed =
        (config.minSilenceSamples / config.frameSize).ceil() + 1;
    return [for (var i = 0; i < needed; i++) (frame(silent), noSpeech)];
  }
}
