import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:notalone/features/capture/domain/audio_level.dart';
import 'package:notalone/features/capture/domain/vad_config.dart';

/// Bornes et énergie d'un segment de parole détecté. Métadonnées seules :
/// le spike ne conserve aucun sample audio (CLAUDE.md règle 2) ; MVP-08
/// ajoutera le buffer nécessaire au STT.
@immutable
class SpeechSegmentBounds {
  const SpeechSegmentBounds({
    required this.tStartMs,
    required this.tEndMs,
    required this.energyDbfs,
  });

  final int tStartMs;

  final int tEndMs;

  /// Énergie RMS en dBFS sur la partie parlée du segment (micro-pauses
  /// internes comprises, silence de clôture exclu).
  final double energyDbfs;

  int get durationMs => tEndMs - tStartMs;
}

@immutable
sealed class SegmenterEvent {
  const SegmenterEvent();
}

/// Début de parole confirmé après `minSpeechMs` de parole cumulée,
/// horodaté rétroactivement au vrai début (pas à la confirmation).
final class SpeechStarted extends SegmenterEvent {
  const SpeechStarted({required this.tStartMs});

  final int tStartMs;
}

final class SpeechEnded extends SegmenterEvent {
  const SpeechEnded({required this.segment});

  final SpeechSegmentBounds segment;
}

enum _SegmenterState { silence, candidateSpeech, speech }

/// Machine à états silence/parole alimentée par les probabilités du VAD
/// (cf. cowork/02-architecture.md §1). Pur Dart, indépendante du moteur :
/// elle survit au spike MVP-02 et sera reprise par MVP-08.
///
/// Hystérésis : un segment démarre au-dessus de `speechStartProbability`
/// mais ne se clôt qu'en dessous de `speechEndProbability`, après
/// `minSilenceMs` de silence continu. Un candidat plus court que
/// `minSpeechMs` est abandonné sans événement.
class SpeechSegmenter {
  SpeechSegmenter({required this._config});

  final VadConfig _config;

  _SegmenterState _state = _SegmenterState.silence;
  int _elapsedSamples = 0;
  int _segmentStartSample = 0;
  int _lastSpeechEndSample = 0;
  int _speechRunSamples = 0;
  int _silenceRunSamples = 0;

  // Énergie : somme des carrés « commise » (jusqu'à la dernière frame parlée)
  // et somme en attente pendant un silence non encore décidé (micro-pause ?).
  double _committedSumSquares = 0;
  int _committedSamples = 0;
  double _pendingSumSquares = 0;
  int _pendingSamples = 0;

  /// Traite une frame et retourne l'événement de segmentation éventuel.
  SegmenterEvent? addFrame(Float32List samples, double speechProbability) {
    if (samples.isEmpty) return null;
    final frameStart = _elapsedSamples;
    _elapsedSamples += samples.length;

    switch (_state) {
      case _SegmenterState.silence:
        if (speechProbability >= _config.speechStartProbability) {
          _state = _SegmenterState.candidateSpeech;
          _segmentStartSample = frameStart;
          _speechRunSamples = 0;
          _committedSumSquares = 0;
          _committedSamples = 0;
          return _accumulateSpeech(samples);
        }
        return null;

      case _SegmenterState.candidateSpeech:
        // Même seuil bas que l'état parole : un creux d'attaque au-dessus de
        // speechEndProbability ne fait pas avorter un vrai début de phrase.
        if (speechProbability >= _config.speechEndProbability) {
          return _accumulateSpeech(samples);
        }
        _state = _SegmenterState.silence;
        return null;

      case _SegmenterState.speech:
        if (speechProbability >= _config.speechEndProbability) {
          _commitPendingSilence();
          return _accumulateSpeech(samples);
        }
        _silenceRunSamples += samples.length;
        _accumulatePending(samples);
        if (_silenceRunSamples >= _config.minSilenceSamples) {
          return _endSegment();
        }
        return null;
    }
  }

  /// Clôt le segment en cours (arrêt de la capture) ; un candidat non
  /// confirmé est abandonné.
  SegmenterEvent? flush() {
    final event = _state == _SegmenterState.speech ? _endSegment() : null;
    _state = _SegmenterState.silence;
    return event;
  }

  /// Réinitialise tout, y compris l'horloge interne (nouveau flux).
  void reset() {
    _state = _SegmenterState.silence;
    _elapsedSamples = 0;
    _segmentStartSample = 0;
    _lastSpeechEndSample = 0;
    _speechRunSamples = 0;
    _silenceRunSamples = 0;
    _committedSumSquares = 0;
    _committedSamples = 0;
    _pendingSumSquares = 0;
    _pendingSamples = 0;
  }

  SegmenterEvent? _accumulateSpeech(Float32List samples) {
    _speechRunSamples += samples.length;
    _silenceRunSamples = 0;
    _lastSpeechEndSample = _elapsedSamples;
    var sumSquares = 0.0;
    for (final sample in samples) {
      sumSquares += sample * sample;
    }
    _committedSumSquares += sumSquares;
    _committedSamples += samples.length;

    if (_state == _SegmenterState.candidateSpeech &&
        _speechRunSamples >= _config.minSpeechSamples) {
      _state = _SegmenterState.speech;
      return SpeechStarted(tStartMs: _msFromSamples(_segmentStartSample));
    }
    return null;
  }

  void _accumulatePending(Float32List samples) {
    for (final sample in samples) {
      _pendingSumSquares += sample * sample;
    }
    _pendingSamples += samples.length;
  }

  // Micro-pause plus courte que minSilenceMs : elle fait partie du segment,
  // son énergie est intégrée.
  void _commitPendingSilence() {
    _committedSumSquares += _pendingSumSquares;
    _committedSamples += _pendingSamples;
    _pendingSumSquares = 0;
    _pendingSamples = 0;
  }

  SpeechEnded _endSegment() {
    final segment = SpeechSegmentBounds(
      tStartMs: _msFromSamples(_segmentStartSample),
      tEndMs: _msFromSamples(_lastSpeechEndSample),
      energyDbfs: _committedSamples == 0
          ? AudioLevel.floorDbfs
          : AudioLevel.dbfsFromMeanSquare(
              _committedSumSquares / _committedSamples,
            ),
    );
    _state = _SegmenterState.silence;
    _silenceRunSamples = 0;
    _pendingSumSquares = 0;
    _pendingSamples = 0;
    _committedSumSquares = 0;
    _committedSamples = 0;
    return SpeechEnded(segment: segment);
  }

  int _msFromSamples(int samples) => samples * 1000 ~/ _config.sampleRate;
}
