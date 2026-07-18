import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:notalone/core/command/command.dart';
import 'package:notalone/core/result/failure.dart';
import 'package:notalone/core/result/result.dart';
import 'package:notalone/features/capture/domain/audio_level.dart';
import 'package:notalone/features/capture/domain/mic_audio_source.dart';
import 'package:notalone/features/capture/domain/speech_segmenter.dart';
import 'package:notalone/features/capture/domain/vad_config.dart';
import 'package:notalone/features/capture/domain/vad_service.dart';

/// ViewModel de l'écran de debug du spike MVP-02 (jetable).
/// Orchestration mic → VAD → segmenteur, à déplacer dans un
/// `CaptureSpeechUseCase` propre en MVP-08.
class VadDebugViewModel extends ChangeNotifier {
  VadDebugViewModel({
    required this._mic,
    required this._vad,
    required this._config,
  }) : _segmenter = SpeechSegmenter(config: _config) {
    startCommand = Command0(_start);
    stopCommand = Command0(_stop);
  }

  final MicAudioSource _mic;
  final VadService _vad;
  final VadConfig _config;
  final SpeechSegmenter _segmenter;

  late final Command0<void> startCommand;
  late final Command0<void> stopCommand;

  bool _capturing = false;
  bool get isCapturing => _capturing;

  double _levelDbfs = AudioLevel.floorDbfs;
  double get levelDbfs => _levelDbfs;

  double _speechProbability = 0;
  double get speechProbability => _speechProbability;

  bool _speechActive = false;
  bool get isSpeechActive => _speechActive;

  /// Erreur survenue en cours de flux (inférence…) : la capture est alors
  /// arrêtée et la cause exposée à la vue.
  Failure? _streamFailure;
  Failure? get streamFailure => _streamFailure;

  final List<SpeechSegmentBounds> _segments = [];
  List<SpeechSegmentBounds> get segments => List.unmodifiable(_segments);

  Future<void>? _loop;

  Future<Result<void>> _start() async {
    if (_capturing) return const Result.ok(null);
    final initialized = await _vad.initialize();
    if (initialized case Err(:final failure)) return Result.err(failure);

    final started = await _mic.start(
      sampleRate: _config.sampleRate,
      frameSize: _config.frameSize,
    );
    switch (started) {
      case Err(:final failure):
        return Result.err(failure);
      case Ok(:final value):
        _segments.clear();
        _segmenter.reset();
        await _vad.reset();
        _streamFailure = null;
        _capturing = true;
        _loop = _processFrames(value);
        notifyListeners();
        return const Result.ok(null);
    }
  }

  Future<Result<void>> _stop() async {
    if (!_capturing) return const Result.ok(null);
    _capturing = false;
    await _mic.stop();
    await _loop;
    return const Result.ok(null);
  }

  Future<void> _processFrames(Stream<Float32List> frames) async {
    await for (final frame in frames) {
      if (!_capturing) break;
      _levelDbfs = AudioLevel.rmsDbfs(frame);
      final prediction = await _vad.predictSpeechProbability(frame);
      if (prediction case Err(:final failure)) {
        _streamFailure = failure;
        unawaited(_mic.stop());
        break;
      }
      final probability = (prediction as Ok<double>).value;
      _speechProbability = probability;
      _handleEvent(_segmenter.addFrame(frame, probability));
      notifyListeners();
    }
    _handleEvent(_segmenter.flush());
    _capturing = false;
    _speechActive = false;
    _levelDbfs = AudioLevel.floorDbfs;
    _speechProbability = 0;
    notifyListeners();
  }

  void _handleEvent(SegmenterEvent? event) {
    switch (event) {
      case SpeechStarted():
        _speechActive = true;
      case SpeechEnded(:final segment):
        _speechActive = false;
        _segments.add(segment);
      case null:
        break;
    }
  }

  @override
  void dispose() {
    _capturing = false;
    unawaited(_mic.stop());
    unawaited(_vad.dispose());
    startCommand.dispose();
    stopCommand.dispose();
    super.dispose();
  }
}
