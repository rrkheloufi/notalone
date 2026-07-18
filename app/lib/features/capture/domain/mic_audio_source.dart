import 'dart:typed_data';

import 'package:notalone/core/result/result.dart';

/// Source audio micro continue. L'audio ne quitte jamais ce téléphone et
/// n'est jamais écrit sur disque (CLAUDE.md règle 2) : le flux reste en
/// mémoire, frame par frame.
abstract interface class MicAudioSource {
  /// Démarre la capture et émet des frames PCM float mono ([-1;1]) de
  /// [frameSize] samples à [sampleRate] Hz.
  Future<Result<Stream<Float32List>>> start({
    required int sampleRate,
    required int frameSize,
  });

  Future<void> stop();
}
