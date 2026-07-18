import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:notalone/features/capture/domain/audio_level.dart';

void main() {
  group('AudioLevel.rmsDbfs', () {
    test('sinusoïde pleine échelle → -3,01 dBFS (RMS = 1/√2)', () {
      final samples = Float32List(512);
      for (var i = 0; i < samples.length; i++) {
        // Période de 64 samples → 8 périodes entières, RMS exact.
        samples[i] = math.sin(2 * math.pi * i / 64);
      }
      expect(AudioLevel.rmsDbfs(samples), closeTo(-3.01, 0.05));
    });

    test('amplitude constante 0,1 → -20 dBFS', () {
      final samples = Float32List(512)..fillRange(0, 512, 0.1);
      expect(AudioLevel.rmsDbfs(samples), closeTo(-20, 0.01));
    });

    test('silence numérique → plancher', () {
      expect(AudioLevel.rmsDbfs(Float32List(512)), AudioLevel.floorDbfs);
    });

    test('frame vide → plancher', () {
      expect(AudioLevel.rmsDbfs(Float32List(0)), AudioLevel.floorDbfs);
    });
  });

  group('AudioLevel.dbfsFromMeanSquare', () {
    test('carré moyen 0,25 → -6,02 dBFS', () {
      expect(AudioLevel.dbfsFromMeanSquare(0.25), closeTo(-6.02, 0.01));
    });

    test('borné au plancher pour les valeurs infimes', () {
      expect(AudioLevel.dbfsFromMeanSquare(1e-30), AudioLevel.floorDbfs);
    });
  });
}
