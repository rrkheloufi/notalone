import 'dart:async';
import 'dart:typed_data';

import 'package:notalone/core/result/failure.dart';
import 'package:notalone/core/result/result.dart';
import 'package:notalone/features/capture/domain/background_capture_guard.dart';
import 'package:notalone/features/capture/domain/mic_audio_source.dart';
import 'package:notalone/features/capture/domain/vad_service.dart';

/// Micro piloté par le test : on lui pousse les frames une à une et on
/// déclenche les interruptions à la main.
class FakeMicAudioSource implements MicAudioSource {
  FakeMicAudioSource({this.failure});

  /// Si non nulle, `start()` échoue avec cette panne.
  Failure? failure;

  final _states = StreamController<MicSourceState>.broadcast();
  StreamController<Float32List>? _frames;

  int startCount = 0;
  int stopCount = 0;
  bool get isRunning => _frames != null && !_frames!.isClosed;

  @override
  Stream<MicSourceState> get state => _states.stream;

  @override
  Future<Result<Stream<Float32List>>> start({
    required int sampleRate,
    required int frameSize,
  }) async {
    startCount++;
    final failure = this.failure;
    if (failure != null) return Result.err(failure);
    _frames = StreamController<Float32List>();
    return Result.ok(_frames!.stream);
  }

  @override
  Future<void> stop() async {
    stopCount++;
    final frames = _frames;
    _frames = null;
    // Sans `await` : le vrai datasource arrête le recorder, il n'attend pas
    // qu'un auditeur — parfois déjà parti — accuse réception de la fin de flux.
    unawaited(frames?.close());
  }

  /// Pousse une frame et rend la main une fois qu'elle a été consommée.
  Future<void> emit(Float32List frame) async {
    emitSync(frame);
    await pump();
  }

  /// Pousse une frame sans attendre : en widget test c'est
  /// `tester.pumpAndSettle()` qui déroule la boucle d'événements.
  void emitSync(Float32List frame) => _frames?.add(frame);

  void interrupt() => _states.add(MicSourceState.interrupted);

  void resume() => _states.add(MicSourceState.recording);

  /// Laisse tourner la boucle d'événements : la consommation d'une frame
  /// traverse plusieurs `await` (inférence VAD).
  static Future<void> pump() async {
    for (var i = 0; i < 8; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<void> dispose() async {
    await stop();
    await _states.close();
  }
}

/// VAD scripté : rend les probabilités dans l'ordre où on les lui a données,
/// puis 0 une fois la liste épuisée.
class FakeVadService implements VadService {
  FakeVadService({List<double>? probabilities, this.initializeFailure})
    : _probabilities = [...?probabilities];

  final List<double> _probabilities;

  Failure? initializeFailure;

  /// Si non nulle, l'inférence échoue à partir de l'appel n° [failAtCall].
  Failure? inferenceFailure;
  int failAtCall = 0;

  int initializeCount = 0;
  int resetCount = 0;
  int disposeCount = 0;
  int _calls = 0;

  void script(List<double> probabilities) {
    _probabilities
      ..clear()
      ..addAll(probabilities);
  }

  @override
  Future<Result<void>> initialize() async {
    initializeCount++;
    final failure = initializeFailure;
    return failure == null ? const Result.ok(null) : Result.err(failure);
  }

  @override
  Future<Result<double>> predictSpeechProbability(Float32List frame) async {
    _calls++;
    final failure = inferenceFailure;
    if (failure != null && _calls >= failAtCall) return Result.err(failure);
    if (_probabilities.isEmpty) return const Result.ok(0);
    return Result.ok(_probabilities.removeAt(0));
  }

  @override
  Future<void> reset() async => resetCount++;

  @override
  Future<void> dispose() async => disposeCount++;
}

class FakeBackgroundCaptureGuard implements BackgroundCaptureGuard {
  Failure? acquireFailure;
  int acquireCount = 0;
  int releaseCount = 0;
  int exemptionRequests = 0;
  bool batteryOptimizationDisabled = true;

  bool get isHeld => acquireCount > releaseCount;

  @override
  Future<Result<void>> acquire() async {
    acquireCount++;
    final failure = acquireFailure;
    return failure == null ? const Result.ok(null) : Result.err(failure);
  }

  @override
  Future<void> release() async => releaseCount++;

  @override
  Future<bool> isBatteryOptimizationDisabled() async =>
      batteryOptimizationDisabled;

  @override
  Future<void> requestBatteryOptimizationExemption() async =>
      exemptionRequests++;
}
