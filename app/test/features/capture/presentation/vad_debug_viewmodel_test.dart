import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:notalone/core/result/result.dart';
import 'package:notalone/features/capture/domain/capture_failure.dart';
import 'package:notalone/features/capture/domain/mic_audio_source.dart';
import 'package:notalone/features/capture/domain/vad_config.dart';
import 'package:notalone/features/capture/domain/vad_service.dart';
import 'package:notalone/features/capture/presentation/vad_debug_viewmodel.dart';

const config = VadConfig();

Float32List frameOf(double amplitude) =>
    Float32List(config.frameSize)..fillRange(0, config.frameSize, amplitude);

final class _FakeMic implements MicAudioSource {
  StreamController<Float32List>? _controller;
  Result<Stream<Float32List>>? nextStartResult;
  bool startCalled = false;
  int stopCalls = 0;

  @override
  Future<Result<Stream<Float32List>>> start({
    required int sampleRate,
    required int frameSize,
  }) async {
    startCalled = true;
    final preset = nextStartResult;
    if (preset != null) return preset;
    _controller = StreamController<Float32List>();
    return Result.ok(_controller!.stream);
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    await _controller?.close();
    _controller = null;
  }

  void add(Float32List frame) => _controller!.add(frame);

  Future<void> close() async => _controller?.close();
}

final class _ScriptedVad implements VadService {
  _ScriptedVad(this.probabilities);

  final List<double> probabilities;
  int _index = 0;

  Result<void> initResult = const Result.ok(null);
  Result<double>? forcedPrediction;
  bool disposed = false;
  int resets = 0;

  @override
  Future<Result<void>> initialize() async => initResult;

  @override
  Future<Result<double>> predictSpeechProbability(Float32List frame) async {
    final forced = forcedPrediction;
    if (forced != null) return forced;
    final probability = _index < probabilities.length
        ? probabilities[_index++]
        : probabilities.last;
    return Result.ok(probability);
  }

  @override
  Future<void> reset() async => resets++;

  @override
  Future<void> dispose() async => disposed = true;
}

void main() {
  test('start → capture, parole détectée, segment clos, stop', () async {
    final mic = _FakeMic();
    final vad = _ScriptedVad([
      for (var i = 0; i < 7; i++) 0.9,
      for (var i = 0; i < 19; i++) 0.01,
    ]);
    final viewModel = VadDebugViewModel(mic: mic, vad: vad, config: config);

    await viewModel.startCommand.execute();
    expect(viewModel.startCommand.completed, isTrue);
    expect(viewModel.isCapturing, isTrue);
    expect(vad.resets, 1);

    for (var i = 0; i < 7; i++) {
      mic.add(frameOf(0.5));
    }
    await pumpEventQueue();
    expect(viewModel.isSpeechActive, isTrue);
    expect(viewModel.speechProbability, 0.9);
    expect(viewModel.levelDbfs, closeTo(-6.02, 0.05));

    for (var i = 0; i < 19; i++) {
      mic.add(frameOf(0));
    }
    await pumpEventQueue();
    expect(viewModel.isSpeechActive, isFalse);
    expect(viewModel.segments, hasLength(1));
    expect(viewModel.segments.single.energyDbfs, closeTo(-6.02, 0.05));

    await viewModel.stopCommand.execute();
    expect(viewModel.isCapturing, isFalse);
    expect(mic.stopCalls, greaterThanOrEqualTo(1));
  });

  test('permission micro refusée → échec exposé, pas de capture', () async {
    final mic = _FakeMic()
      ..nextStartResult = const Result.err(MicPermissionFailure());
    final viewModel = VadDebugViewModel(
      mic: mic,
      vad: _ScriptedVad([0.5]),
      config: config,
    );

    await viewModel.startCommand.execute();

    expect(viewModel.startCommand.error, isTrue);
    expect(
      viewModel.startCommand.result?.failureOrNull,
      isA<MicPermissionFailure>(),
    );
    expect(viewModel.isCapturing, isFalse);
  });

  test(
    'échec d initialisation du VAD → le micro n est jamais démarré',
    () async {
      final mic = _FakeMic();
      final vad = _ScriptedVad([0.5])
        ..initResult = const Result.err(VadInitializationFailure('modèle'));
      final viewModel = VadDebugViewModel(mic: mic, vad: vad, config: config);

      await viewModel.startCommand.execute();

      expect(viewModel.startCommand.error, isTrue);
      expect(mic.startCalled, isFalse);
      expect(viewModel.isCapturing, isFalse);
    },
  );

  test(
    'erreur d inférence en cours de flux → capture arrêtée, cause exposée',
    () async {
      final mic = _FakeMic();
      final vad = _ScriptedVad([0.5])
        ..forcedPrediction = const Result.err(VadInferenceFailure('boom'));
      final viewModel = VadDebugViewModel(mic: mic, vad: vad, config: config);

      await viewModel.startCommand.execute();
      mic.add(frameOf(0.5));
      await pumpEventQueue();

      expect(viewModel.streamFailure, isA<VadInferenceFailure>());
      expect(viewModel.isCapturing, isFalse);
    },
  );

  test('flux clos de l extérieur → segment en cours fermé par flush', () async {
    final mic = _FakeMic();
    final vad = _ScriptedVad([0.9]);
    final viewModel = VadDebugViewModel(mic: mic, vad: vad, config: config);

    await viewModel.startCommand.execute();
    for (var i = 0; i < 10; i++) {
      mic.add(frameOf(0.5));
    }
    await pumpEventQueue();
    expect(viewModel.isSpeechActive, isTrue);

    await mic.close();
    await pumpEventQueue();

    expect(viewModel.isCapturing, isFalse);
    expect(viewModel.segments, hasLength(1));
    expect(viewModel.segments.single.tEndMs, 10 * 32);
  });
}
