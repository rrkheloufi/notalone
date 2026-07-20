import 'dart:async';
import 'dart:collection';

import 'package:notalone/core/result/failure.dart';
import 'package:notalone/core/result/result.dart';
import 'package:notalone/features/capture/domain/speech_segment.dart';
import 'package:notalone/features/capture/domain/stt_config.dart';
import 'package:notalone/features/capture/domain/stt_engine.dart';
import 'package:notalone/features/capture/domain/stt_failure.dart';
import 'package:notalone/features/capture/domain/transcribed_segment.dart';

/// Soumet au moteur STT les segments que la capture produit, **un par un**.
///
/// Sérialisé par construction : les moteurs natifs n'ouvrent qu'une session de
/// reconnaissance à la fois, et deux segments concurrents se voleraient la
/// ressource. La file est bornée ([SttConfig.maxPendingSegments]) — un moteur
/// plus lent que la parole ne doit pas faire enfler la mémoire d'un repas de
/// 2 h (doc 03 R1).
///
/// Pur Dart : le moteur est une interface, tout le comportement est rejouable
/// en test.
class TranscribeSegmentsUseCase {
  TranscribeSegmentsUseCase({
    required this._engine,
    this._config = const SttConfig(),
  });

  final SttEngine _engine;
  final SttConfig _config;

  final Queue<SpeechSegment> _pending = Queue<SpeechSegment>();
  final _transcriptions = StreamController<TranscribedSegment>.broadcast();
  final _failures = StreamController<Failure>.broadcast();

  /// Segments transcrits, dans l'ordre où ils ont été captés.
  Stream<TranscribedSegment> get transcriptions => _transcriptions.stream;

  /// Pannes par segment. Émises plutôt que retournées : `submit()` rend la
  /// main tout de suite, la transcription lui survit.
  Stream<Failure> get failures => _failures.stream;

  bool _draining = false;

  int get pendingCount => _pending.length;

  /// Segments jetés faute de place dans la file. Objective la calibration
  /// MVP-15 : un compteur qui grimpe dit que le moteur ne suit pas la parole.
  int _droppedSegments = 0;
  int get droppedSegments => _droppedSegments;

  /// Segments transcrits en un texte vide (bruit de couverts, rire) : le
  /// moteur n'a pas échoué, il n'y avait rien à dire. Ils ne sont pas émis —
  /// une bulle vide dans le fil du lecteur ne serait que du bruit visuel.
  int _emptySegments = 0;
  int get emptySegments => _emptySegments;

  bool _disposed = false;

  SttCapabilities get capabilities => _engine.capabilities;

  /// Disponibilité du moteur et du modèle français. L'écran de capture en
  /// affiche la panne avant même de démarrer le micro.
  Future<Result<void>> prepare() => _engine.prepare();

  /// Met un segment en file. Ne rend jamais d'erreur : la file absorbe, et la
  /// panne éventuelle sort par [failures].
  void submit(SpeechSegment segment) {
    if (_disposed) return;
    _pending.add(segment);
    while (_pending.length > _config.maxPendingSegments) {
      _pending.removeFirst();
      _droppedSegments++;
    }
    unawaited(_drain());
  }

  Future<void> _drain() async {
    if (_draining) return;
    _draining = true;
    try {
      while (_pending.isNotEmpty && !_disposed) {
        await _transcribe(_pending.removeFirst());
      }
    } finally {
      _draining = false;
    }
  }

  Future<void> _transcribe(SpeechSegment segment) async {
    final result = await _engine
        .transcribe(segment)
        .timeout(
          _config.transcriptionTimeout,
          // Un moteur muet ne doit pas retenir les segments suivants : on
          // abandonne celui-ci et la file repart.
          onTimeout: () =>
              Result.err(SttTimeoutFailure(_config.transcriptionTimeoutMs)),
        );
    if (_disposed) return;
    switch (result) {
      case Err(:final failure):
        if (!_failures.isClosed) _failures.add(failure);
      case Ok(:final value):
        if (value.isEmpty) {
          _emptySegments++;
          return;
        }
        if (!_transcriptions.isClosed) {
          _transcriptions.add(TranscribedSegment.of(segment, value));
        }
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    _pending.clear();
    await _engine.dispose();
    await _transcriptions.close();
    await _failures.close();
  }
}
