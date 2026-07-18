import 'dart:typed_data';

import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:notalone/core/result/result.dart';
import 'package:notalone/features/capture/domain/capture_failure.dart';
import 'package:notalone/features/capture/domain/vad_config.dart';
import 'package:notalone/features/capture/domain/vad_service.dart';

/// Silero VAD v5 exécuté via ONNX Runtime (`flutter_onnxruntime`).
///
/// Protocole d'appel aligné sur le wrapper officiel silero-vad (validé
/// contre onnxruntime desktop pendant le spike) : entrée
/// `[1, 64 + frameSize]` avec 64 samples de contexte glissant, état LSTM
/// `[2, 1, 128]` rebouclé entre les frames, `sr` en int64 `[1]`.
class SileroVadService implements VadService {
  SileroVadService({required this._config});

  static const String _assetPath = 'assets/models/silero_vad.onnx';
  static const int _contextSamples = 64;
  static const List<int> _stateShape = [2, 1, 128];

  final VadConfig _config;

  OrtSession? _session;
  Float32List _context = Float32List(_contextSamples);
  Float32List _state = Float32List(2 * 128);

  @override
  Future<Result<void>> initialize() async {
    try {
      _session ??= await OnnxRuntime().createSessionFromAsset(_assetPath);
      return const Result.ok(null);
    } on Exception catch (exception) {
      return Result.err(VadInitializationFailure('$exception'));
    }
  }

  @override
  Future<Result<double>> predictSpeechProbability(Float32List frame) async {
    final session = _session;
    if (session == null) {
      return const Result.err(VadInitializationFailure('non initialisé'));
    }
    final input = Float32List(_contextSamples + frame.length)
      ..setAll(0, _context)
      ..setAll(_contextSamples, frame);

    OrtValue? inputValue;
    OrtValue? stateValue;
    OrtValue? srValue;
    Map<String, OrtValue>? outputs;
    try {
      inputValue = await OrtValue.fromList(input, [1, input.length]);
      stateValue = await OrtValue.fromList(_state, _stateShape);
      srValue = await OrtValue.fromList([_config.sampleRate], [1]);
      outputs = await session.run({
        'input': inputValue,
        'state': stateValue,
        'sr': srValue,
      });

      final probabilities = await outputs['output']!.asFlattenedList();
      final nextState = await outputs['stateN']!.asFlattenedList();
      _state = Float32List.fromList([
        for (final value in nextState) (value as num).toDouble(),
      ]);
      _context = Float32List.fromList(
        input.sublist(input.length - _contextSamples),
      );
      return Result.ok((probabilities.first as num).toDouble());
    } on Exception catch (exception) {
      return Result.err(VadInferenceFailure('$exception'));
    } finally {
      await inputValue?.dispose();
      await stateValue?.dispose();
      await srValue?.dispose();
      for (final value in outputs?.values ?? const <OrtValue>[]) {
        await value.dispose();
      }
    }
  }

  @override
  Future<void> reset() async {
    _context = Float32List(_contextSamples);
    _state = Float32List(2 * 128);
  }

  @override
  Future<void> dispose() async {
    await _session?.close();
    _session = null;
  }
}
