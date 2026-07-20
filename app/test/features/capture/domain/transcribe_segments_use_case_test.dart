import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:notalone/core/result/failure.dart';
import 'package:notalone/features/capture/domain/speech_segment.dart';
import 'package:notalone/features/capture/domain/stt_config.dart';
import 'package:notalone/features/capture/domain/stt_failure.dart';
import 'package:notalone/features/capture/domain/transcribe_segments_use_case.dart';
import 'package:notalone/features/capture/domain/transcribed_segment.dart';

import '../../../helpers/fake_stt_engine.dart';

SpeechSegment segment(String id, {int startMs = 0, double energy = -20}) =>
    SpeechSegment(
      segmentId: id,
      tStartMs: startMs,
      tEndMs: startMs + 1000,
      energyDbfs: energy,
      samples: Float32List(16),
      sampleRate: 16000,
    );

/// Laisse tourner la boucle d'événements : la file traverse plusieurs `await`.
Future<void> pump() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('TranscribeSegmentsUseCase', () {
    test('transcrit un segment et l’émet avec ses métadonnées', () async {
      final engine = FakeSttEngine(texts: ['passe-moi le sel']);
      final useCase = TranscribeSegmentsUseCase(engine: engine);
      final emitted = <TranscribedSegment>[];
      useCase.transcriptions.listen(emitted.add);

      useCase.submit(segment('s1', startMs: 1000, energy: -14));
      await pump();

      expect(emitted, hasLength(1));
      expect(emitted.single.text, 'passe-moi le sel');
      expect(emitted.single.segmentId, 's1');
      expect(emitted.single.tStartMs, 1000);
      expect(emitted.single.tEndMs, 2000);
      expect(emitted.single.energyDbfs, -14);
      expect(emitted.single.transcription.engine, 'fake');

      await useCase.dispose();
    });

    test('sérialise les segments et respecte leur ordre', () async {
      final engine = FakeSttEngine(texts: ['un', 'deux', 'trois'])..hold();
      final useCase = TranscribeSegmentsUseCase(engine: engine);
      final emitted = <String>[];
      useCase.transcriptions.listen((entry) => emitted.add(entry.text));

      useCase
        ..submit(segment('s1'))
        ..submit(segment('s2'))
        ..submit(segment('s3'));
      await pump();

      // Le premier segment tient la file : aucun autre n'est parti au moteur.
      expect(engine.transcribedIds, isEmpty);
      expect(useCase.pendingCount, 2);

      engine.release();
      await pump();

      expect(engine.transcribedIds, ['s1', 's2', 's3']);
      expect(emitted, ['un', 'deux', 'trois']);
      expect(useCase.pendingCount, 0);

      await useCase.dispose();
    });

    test('jette le plus ancien quand la file déborde', () async {
      final engine = FakeSttEngine()..hold();
      final useCase = TranscribeSegmentsUseCase(
        engine: engine,
        config: const SttConfig(maxPendingSegments: 2),
      );
      final emitted = <String>[];
      useCase.transcriptions.listen((entry) => emitted.add(entry.segmentId));

      for (var i = 1; i <= 5; i++) {
        useCase.submit(segment('s$i'));
      }
      await pump();

      expect(useCase.droppedSegments, 2);
      expect(useCase.pendingCount, 2);

      engine.release();
      await pump();

      // s1 est parti au moteur avant le débordement ; s2 et s3 ont été jetés.
      expect(emitted, ['s1', 's4', 's5']);

      await useCase.dispose();
    });

    test('n’émet pas un texte vide mais le compte', () async {
      final engine = FakeSttEngine(texts: ['', '   ', 'bonjour']);
      final useCase = TranscribeSegmentsUseCase(engine: engine);
      final emitted = <String>[];
      useCase.transcriptions.listen((entry) => emitted.add(entry.text));

      useCase
        ..submit(segment('s1'))
        ..submit(segment('s2'))
        ..submit(segment('s3'));
      await pump();

      expect(emitted, ['bonjour']);
      expect(useCase.emptySegments, 2);

      await useCase.dispose();
    });

    test('émet la panne d’un segment sans arrêter les suivants', () async {
      final engine = FakeSttEngine(texts: ['un', 'deux'])
        ..transcriptionFailure = const SttTranscriptionFailure('moteur occupé')
        ..failAtCall = 1;
      final useCase = TranscribeSegmentsUseCase(engine: engine);
      final failures = <Failure>[];
      final emitted = <String>[];
      useCase.failures.listen(failures.add);
      useCase.transcriptions.listen((entry) => emitted.add(entry.text));

      useCase.submit(segment('s1'));
      await pump();

      expect(failures, hasLength(1));
      expect(failures.single, isA<SttTranscriptionFailure>());

      engine.transcriptionFailure = null;
      useCase.submit(segment('s2'));
      await pump();

      expect(emitted, ['un']);

      await useCase.dispose();
    });

    test('abandonne un segment que le moteur ne rend jamais', () async {
      final useCase = TranscribeSegmentsUseCase(
        engine: HangingSttEngine(),
        config: const SttConfig(transcriptionTimeoutMs: 40),
      );
      final failures = <Failure>[];
      useCase.failures.listen(failures.add);

      useCase.submit(segment('s1'));
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(failures.single, isA<SttTimeoutFailure>());
      expect((failures.single as SttTimeoutFailure).elapsedMs, 40);

      await useCase.dispose();
    });

    test('un moteur bloqué ne retient pas les segments suivants', () async {
      final useCase = TranscribeSegmentsUseCase(
        engine: HangingSttEngine(),
        config: const SttConfig(transcriptionTimeoutMs: 40),
      );
      final failures = <Failure>[];
      useCase.failures.listen(failures.add);

      useCase
        ..submit(segment('s1'))
        ..submit(segment('s2'));
      await Future<void>.delayed(const Duration(milliseconds: 200));

      // Sans le délai de garde, le second n'aurait jamais atteint le moteur.
      expect(failures, hasLength(2));

      await useCase.dispose();
    });

    test('relaie prepare et les capacités du moteur', () async {
      final engine = FakeSttEngine();
      final useCase = TranscribeSegmentsUseCase(engine: engine);

      expect((await useCase.prepare()).isOk, isTrue);
      expect(engine.prepareCount, 1);
      expect(useCase.capabilities.engine, 'fake');

      engine.prepareFailure = const SttModelMissingFailure('fr-FR');
      final failed = await useCase.prepare();
      expect(failed.failureOrNull, isA<SttModelMissingFailure>());

      await useCase.dispose();
    });

    test(
      'dispose libère le moteur et ignore les soumissions suivantes',
      () async {
        final engine = FakeSttEngine();
        final useCase = TranscribeSegmentsUseCase(engine: engine);

        await useCase.dispose();
        useCase.submit(segment('s1'));
        await pump();

        expect(engine.disposeCount, 1);
        expect(engine.transcribedIds, isEmpty);
        expect(useCase.pendingCount, 0);
      },
    );
  });
}
