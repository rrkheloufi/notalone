import 'dart:async';

import 'package:notalone/core/result/failure.dart';
import 'package:notalone/core/result/result.dart';
import 'package:notalone/features/capture/domain/speech_segment.dart';
import 'package:notalone/features/capture/domain/stt_engine.dart';
import 'package:notalone/features/capture/domain/transcription.dart';

/// Moteur STT scripté : rend les textes qu'on lui donne, dans l'ordre, et
/// permet de retenir une transcription pour observer la file d'attente.
class FakeSttEngine implements SttEngine {
  FakeSttEngine({
    List<String>? texts,
    this.prepareFailure,
    SttCapabilities? capabilities,
  }) : _texts = [...?texts],
       capabilities =
           capabilities ??
           const SttCapabilities(engine: 'fake', languageTag: 'fr-FR');

  final List<String> _texts;

  @override
  final SttCapabilities capabilities;

  Failure? prepareFailure;

  /// Si non nulle, la transcription échoue à partir de l'appel n° [failAtCall].
  Failure? transcriptionFailure;
  int failAtCall = 1;

  /// Segments soumis, dans l'ordre : c'est ce qui prouve la sérialisation.
  final List<String> transcribedIds = [];

  int prepareCount = 0;
  int disposeCount = 0;
  int _calls = 0;

  /// Quand elle est posée, chaque transcription attend son déblocage.
  Completer<void>? _gate;

  void script(List<String> texts) => _texts
    ..clear()
    ..addAll(texts);

  /// Bloque les transcriptions à venir jusqu'à [release].
  void hold() => _gate = Completer<void>();

  void release() {
    final gate = _gate;
    _gate = null;
    if (gate != null && !gate.isCompleted) gate.complete();
  }

  @override
  Future<Result<void>> prepare() async {
    prepareCount++;
    final failure = prepareFailure;
    return failure == null ? const Result.ok(null) : Result.err(failure);
  }

  @override
  Future<Result<Transcription>> transcribe(SpeechSegment segment) async {
    _calls++;
    final gate = _gate;
    if (gate != null) await gate.future;
    transcribedIds.add(segment.segmentId);
    final failure = transcriptionFailure;
    if (failure != null && _calls >= failAtCall) return Result.err(failure);
    final text = _texts.isEmpty
        ? 'texte ${segment.segmentId}'
        : _texts.removeAt(0);
    return Result.ok(
      Transcription(text: text, engine: capabilities.engine),
    );
  }

  @override
  Future<void> dispose() async => disposeCount++;
}

/// Moteur qui ne rend jamais la main : sert à vérifier le délai de garde.
class HangingSttEngine implements SttEngine {
  @override
  SttCapabilities get capabilities =>
      const SttCapabilities(engine: 'hanging', languageTag: 'fr-FR');

  @override
  Future<Result<void>> prepare() async => const Result.ok(null);

  @override
  Future<Result<Transcription>> transcribe(SpeechSegment segment) =>
      Completer<Result<Transcription>>().future;

  @override
  Future<void> dispose() async {}
}
