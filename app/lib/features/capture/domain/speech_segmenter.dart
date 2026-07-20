import 'dart:math' as math;
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:notalone/features/capture/domain/audio_level.dart';
import 'package:notalone/features/capture/domain/vad_config.dart';

/// Segment de parole tel que le segmenteur le voit : horodaté **depuis le
/// début du flux**, pas en temps epoch. `CaptureSpeechUseCase` le convertit
/// en `SpeechSegment` daté et identifié — le segmenteur, lui, reste ignorant
/// de l'horloge.
@immutable
class RawSpeechSegment {
  const RawSpeechSegment({
    required this.tStartMs,
    required this.tEndMs,
    required this.energyDbfs,
    required this.samples,
  });

  final int tStartMs;

  final int tEndMs;

  /// Énergie RMS en dBFS sur la partie parlée du segment (micro-pauses
  /// internes comprises, silence de clôture exclu).
  final double energyDbfs;

  /// Audio du segment. Volontairement **plus large que [tStartMs]–[tEndMs]** :
  /// il porte en tête le pré-roll (`VadConfig.preRollMs`) et en queue le
  /// silence de clôture, parce qu'un moteur STT transcrit mieux une phrase
  /// qui n'est rognée à aucun bout. Les bornes, elles, restent strictement
  /// celles de la parole : c'est sur elles que la déduplication mesure le
  /// chevauchement (cf. cowork/02-architecture.md §5).
  final Float32List samples;

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

  final RawSpeechSegment segment;
}

enum _SegmenterState { silence, candidateSpeech, speech }

/// Machine à états silence/parole alimentée par les probabilités du VAD
/// (cf. cowork/02-architecture.md §1). Pur Dart, indépendante du moteur.
///
/// Hystérésis : un segment démarre au-dessus de `speechStartProbability`
/// mais ne se clôt qu'en dessous de `speechEndProbability`, après
/// `minSilenceMs` de silence continu. Un candidat plus court que
/// `minSpeechMs` est abandonné sans événement.
///
/// Au-delà de `maxSegmentMs` le segment est coupé d'office et la parole
/// enchaîne sur le suivant sans repasser par la confirmation : une tirade
/// ininterrompue ne doit ni gonfler indéfiniment en mémoire ni faire
/// attendre le lecteur.
class SpeechSegmenter {
  SpeechSegmenter({required VadConfig config})
    : _config = config,
      _preRoll = Float32List(config.preRollSamples);

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

  // Audio du segment en cours, gardé en morceaux et concaténé à l'émission :
  // recopier un buffer qui grandit à chaque frame coûterait cher sur 15 s.
  final List<Float32List> _chunks = [];
  int _chunkSamples = 0;

  // Tampon circulaire du pré-roll : les derniers `preRollSamples` samples vus,
  // quel que soit l'état.
  final Float32List _preRoll;
  int _preRollCursor = 0;
  int _preRollFilled = 0;

  /// Vraie tant qu'une prise de parole est en cours. Une découpe forcée
  /// n'émet pas de nouveau [SpeechStarted] — la vue doit donc lire cet état
  /// plutôt que de le déduire des événements.
  bool get isSpeaking => _state == _SegmenterState.speech;

  /// Traite une frame et retourne l'événement de segmentation éventuel.
  SegmenterEvent? addFrame(Float32List samples, double speechProbability) {
    if (samples.isEmpty) return null;
    final frameStart = _elapsedSamples;
    _elapsedSamples += samples.length;
    final event = _process(samples, speechProbability, frameStart);
    _pushPreRoll(samples);
    return event;
  }

  SegmenterEvent? _process(
    Float32List samples,
    double speechProbability,
    int frameStart,
  ) {
    switch (_state) {
      case _SegmenterState.silence:
        if (speechProbability >= _config.speechStartProbability) {
          _state = _SegmenterState.candidateSpeech;
          _segmentStartSample = frameStart;
          _speechRunSamples = 0;
          _committedSumSquares = 0;
          _committedSamples = 0;
          _startBuffer();
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
        _discardBuffer();
        return null;

      case _SegmenterState.speech:
        final forced = _cutIfTooLong(frameStart);
        if (speechProbability >= _config.speechEndProbability) {
          _commitPendingSilence();
          _accumulateSpeech(samples);
          return forced;
        }
        _silenceRunSamples += samples.length;
        _accumulatePending(samples);
        if (_silenceRunSamples >= _config.minSilenceSamples) {
          // La découpe forcée l'emporte : elle est déjà partie, le reliquat
          // de silence clôt simplement le segment suivant au tour d'après.
          return forced ?? _endSegment();
        }
        return forced;
    }
  }

  /// Clôt le segment en cours (arrêt de la capture) ; un candidat non
  /// confirmé est abandonné.
  SegmenterEvent? flush() {
    final event = _state == _SegmenterState.speech ? _endSegment() : null;
    if (event == null) _discardBuffer();
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
    _discardBuffer();
    _preRollCursor = 0;
    _preRollFilled = 0;
  }

  /// Coupe le segment s'il atteint `maxSegmentMs`, et rouvre aussitôt un
  /// segment à cet instant : la parole n'est pas interrompue, seul le
  /// découpage l'est.
  SpeechEnded? _cutIfTooLong(int frameStart) {
    if (_elapsedSamples - _segmentStartSample <= _config.maxSegmentSamples) {
      return null;
    }
    final silenceRun = _silenceRunSamples;
    final ended = _endSegment();
    _state = _SegmenterState.speech;
    _segmentStartSample = frameStart;
    _lastSpeechEndSample = frameStart;
    _silenceRunSamples = silenceRun;
    _startBuffer(withPreRoll: false);
    return ended;
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
    _appendToBuffer(samples);

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
    _appendToBuffer(samples);
  }

  // Micro-pause plus courte que minSilenceMs : elle fait partie du segment,
  // son énergie est intégrée. L'audio, lui, y était déjà.
  void _commitPendingSilence() {
    _committedSumSquares += _pendingSumSquares;
    _committedSamples += _pendingSamples;
    _pendingSumSquares = 0;
    _pendingSamples = 0;
  }

  SpeechEnded _endSegment() {
    final segment = RawSpeechSegment(
      tStartMs: _msFromSamples(_segmentStartSample),
      tEndMs: _msFromSamples(_lastSpeechEndSample),
      energyDbfs: _committedSamples == 0
          ? AudioLevel.floorDbfs
          : AudioLevel.dbfsFromMeanSquare(
              _committedSumSquares / _committedSamples,
            ),
      samples: _takeBuffer(),
    );
    _state = _SegmenterState.silence;
    _silenceRunSamples = 0;
    _pendingSumSquares = 0;
    _pendingSamples = 0;
    _committedSumSquares = 0;
    _committedSamples = 0;
    return SpeechEnded(segment: segment);
  }

  void _startBuffer({bool withPreRoll = true}) {
    _discardBuffer();
    if (withPreRoll) {
      final preRoll = _readPreRoll();
      if (preRoll.isNotEmpty) _appendToBuffer(preRoll);
    }
  }

  void _appendToBuffer(Float32List samples) {
    _chunks.add(samples);
    _chunkSamples += samples.length;
  }

  void _discardBuffer() {
    _chunks.clear();
    _chunkSamples = 0;
  }

  Float32List _takeBuffer() {
    final buffer = Float32List(_chunkSamples);
    var offset = 0;
    for (final chunk in _chunks) {
      buffer.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }
    _discardBuffer();
    return buffer;
  }

  void _pushPreRoll(Float32List samples) {
    if (_preRoll.isEmpty) return;
    // Une frame plus longue que le tampon : seule sa fin est conservée.
    final start = samples.length > _preRoll.length
        ? samples.length - _preRoll.length
        : 0;
    for (var i = start; i < samples.length; i++) {
      _preRoll[_preRollCursor] = samples[i];
      _preRollCursor = (_preRollCursor + 1) % _preRoll.length;
    }
    _preRollFilled = math.min(
      _preRollFilled + samples.length - start,
      _preRoll.length,
    );
  }

  /// Le tampon circulaire remis à plat, du plus ancien au plus récent.
  Float32List _readPreRoll() {
    if (_preRollFilled == 0) return Float32List(0);
    final out = Float32List(_preRollFilled);
    final oldest =
        (_preRollCursor - _preRollFilled + _preRoll.length) % _preRoll.length;
    for (var i = 0; i < _preRollFilled; i++) {
      out[i] = _preRoll[(oldest + i) % _preRoll.length];
    }
    return out;
  }

  int _msFromSamples(int samples) => samples * 1000 ~/ _config.sampleRate;
}
