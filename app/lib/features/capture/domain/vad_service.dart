import 'dart:typed_data';

import 'package:notalone/core/result/result.dart';

/// Détecteur de parole frame par frame. L'implémentation (Silero ONNX…)
/// vit dans data/ : changer de VAD ne touche que data/ (CLAUDE.md règle 3).
abstract interface class VadService {
  Future<Result<void>> initialize();

  /// Probabilité de parole [0;1] pour une frame PCM float mono de la taille
  /// configurée (`VadConfig.frameSize`). L'implémentation maintient son état
  /// interne entre les frames d'un même flux.
  Future<Result<double>> predictSpeechProbability(Float32List frame);

  /// Réinitialise l'état interne (nouveau flux audio).
  Future<void> reset();

  Future<void> dispose();
}
