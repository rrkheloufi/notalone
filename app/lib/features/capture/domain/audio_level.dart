import 'dart:math' as math;
import 'dart:typed_data';

/// Mesure d'énergie RMS en dBFS (0 dBFS = pleine échelle) sur des samples
/// PCM float mono [-1;1]. Sert au filtre voix proche/lointaine
/// (cf. cowork/02-architecture.md §1) et au vumètre de debug.
abstract final class AudioLevel {
  /// Plancher retourné pour le silence numérique (log(0) sinon).
  static const double floorDbfs = -100;

  static double rmsDbfs(Float32List samples) {
    if (samples.isEmpty) return floorDbfs;
    var sumSquares = 0.0;
    for (final sample in samples) {
      sumSquares += sample * sample;
    }
    return dbfsFromMeanSquare(sumSquares / samples.length);
  }

  static double dbfsFromMeanSquare(double meanSquare) {
    if (meanSquare <= 0) return floorDbfs;
    final dbfs = 10 * math.log(meanSquare) / math.ln10;
    return math.max(dbfs, floorDbfs);
  }
}
