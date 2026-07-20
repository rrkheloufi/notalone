import 'dart:typed_data';

import 'package:notalone/core/result/result.dart';

/// État du micro tel que l'OS le rapporte.
enum MicSourceState {
  /// Le micro capte.
  recording,

  /// L'OS a suspendu la capture (appel entrant, autre app prioritaire).
  /// La reprise est prise en charge par l'implémentation.
  interrupted,

  /// Capture terminée.
  stopped,
}

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

  /// Interruptions et reprises signalées par l'OS, source du `mic_status`
  /// remonté à l'hôte (cf. cowork/03-risques-rgpd-roadmap.md R5).
  Stream<MicSourceState> get state;

  Future<void> stop();
}
