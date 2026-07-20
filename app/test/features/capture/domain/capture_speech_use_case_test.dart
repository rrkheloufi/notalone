import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:notalone/features/capture/domain/capture_failure.dart';
import 'package:notalone/features/capture/domain/capture_speech_use_case.dart';
import 'package:notalone/features/capture/domain/capture_status.dart';
import 'package:notalone/features/capture/domain/speech_segment.dart';
import 'package:notalone/features/capture/domain/vad_config.dart';

import '../../../fixtures/audio_fixtures.dart';
import '../../../helpers/fake_capture_sources.dart';

void main() {
  late FakeMicAudioSource mic;
  late FakeVadService vad;
  late FakeBackgroundCaptureGuard guard;
  late CaptureSpeechUseCase capture;
  late List<SpeechSegment> emitted;
  late List<CaptureStatus> statuses;

  var clock = 1000000;
  var ids = 0;

  CaptureSpeechUseCase build({VadConfig config = const VadConfig()}) {
    final useCase = CaptureSpeechUseCase(
      mic: mic,
      vad: vad,
      guard: guard,
      config: config,
      nowMs: () => clock,
      generateId: () => 'segment-${++ids}',
    );
    emitted = [];
    statuses = [];
    useCase.segments.listen(emitted.add);
    useCase.statuses.listen(statuses.add);
    return useCase;
  }

  /// Joue une suite (frame, probabilité) dans le pipeline.
  Future<void> play(List<(Float32List, double)> script) async {
    vad.script([for (final (_, probability) in script) probability]);
    for (final (frame, _) in script) {
      await mic.emit(frame);
    }
  }

  setUp(() {
    clock = 1000000;
    ids = 0;
    mic = FakeMicAudioSource();
    vad = FakeVadService();
    guard = FakeBackgroundCaptureGuard();
    capture = build();
  });

  tearDown(() async {
    await capture.dispose();
    await mic.dispose();
  });

  group('démarrage', () {
    test('start() prend le garde puis initialise le VAD et le micro', () async {
      final result = await capture.start();

      expect(result.isOk, isTrue);
      expect(guard.isHeld, isTrue);
      expect(vad.initializeCount, 1);
      expect(mic.startCount, 1);
      expect(capture.status, CaptureStatus.active);
    });

    test('micro refusé → panne remontée et garde relâché', () async {
      mic.failure = const MicPermissionFailure();

      final result = await capture.start();

      expect(result.failureOrNull, isA<MicPermissionFailure>());
      expect(guard.isHeld, isFalse, reason: 'pas de service laissé en vie');
      expect(capture.status, CaptureStatus.idle);
    });

    test('VAD non initialisable → panne remontée et garde relâché', () async {
      vad.initializeFailure = const VadInitializationFailure('modèle absent');

      final result = await capture.start();

      expect(result.failureOrNull, isA<VadInitializationFailure>());
      expect(guard.isHeld, isFalse);
      expect(mic.startCount, 0, reason: 'micro jamais ouvert pour rien');
    });

    test('garde refusé → le micro ne démarre pas', () async {
      guard.acquireFailure = const BackgroundCaptureFailure('service refusé');

      final result = await capture.start();

      expect(result.failureOrNull, isA<BackgroundCaptureFailure>());
      expect(mic.startCount, 0);
    });

    test('start() deux fois de suite ne démarre qu une capture', () async {
      await capture.start();
      await capture.start();

      expect(mic.startCount, 1);
    });
  });

  group('segments', () {
    test('une prise de parole produit un segment horodaté en epoch', () async {
      await capture.start();
      await play(AudioFixtures.utterance());

      expect(emitted, hasLength(1));
      final segment = emitted.single;
      expect(segment.segmentId, 'segment-1');
      // 10 frames de 32 ms de parole, comptées depuis l'origine du flux.
      expect(segment.tStartMs, clock);
      expect(segment.tEndMs, clock + 320);
      expect(segment.durationMs, 320);
      expect(segment.sampleRate, 16000);
    });

    test('le segment porte son audio, pré-roll compris', () async {
      await capture.start();
      await play(AudioFixtures.utterance());

      final segment = emitted.single;
      expect(segment.samples, isNotEmpty);
      expect(
        segment.samples.length,
        greaterThan(320 * 16), // plus que la seule parole
        reason: 'pré-roll et silence de clôture inclus',
      );
    });

    test('le silence seul ne produit rien', () async {
      await capture.start();
      await play([
        for (var i = 0; i < 40; i++)
          (AudioFixtures.frame(AudioFixtures.silent), AudioFixtures.noSpeech),
      ]);

      expect(emitted, isEmpty);
    });

    test('deux prises de parole → deux segments distincts', () async {
      await capture.start();
      await play([
        ...AudioFixtures.utterance(),
        ...AudioFixtures.utterance(),
      ]);

      expect(emitted, hasLength(2));
      expect(emitted[0].segmentId, isNot(emitted[1].segmentId));
      expect(emitted[1].tStartMs, greaterThan(emitted[0].tEndMs));
    });
  });

  group('filtre énergie', () {
    test('une voix lointaine mais audible passe le filtre', () async {
      await capture.start();
      await play(
        AudioFixtures.utterance(amplitude: AudioFixtures.distantVoice),
      );

      expect(emitted, hasLength(1));
      expect(emitted.single.energyDbfs, closeTo(-33.98, 0.1));
      expect(capture.discardedSegments, 0);
    });

    test('un bruit de fond sous le plancher est écarté', () async {
      await capture.start();
      await play(AudioFixtures.utterance(amplitude: AudioFixtures.roomNoise));

      expect(emitted, isEmpty);
      expect(capture.discardedSegments, 1);
    });

    test('le seuil retenu est bien celui de la config', () async {
      capture = build(config: const VadConfig(minSegmentEnergyDbfs: -20));
      await capture.start();
      // −34 dBFS : au-dessus du plancher par défaut, sous celui-ci.
      await play(
        AudioFixtures.utterance(amplitude: AudioFixtures.distantVoice),
      );

      expect(emitted, isEmpty);
      expect(capture.discardedSegments, 1);
    });
  });

  group('interruptions', () {
    test('une interruption bascule le statut et clôt le segment', () async {
      await capture.start();
      // En pleine phrase quand l'appel tombe.
      await play([
        for (var i = 0; i < 10; i++)
          (
            AudioFixtures.frame(AudioFixtures.loudVoice),
            AudioFixtures.speech,
          ),
      ]);
      mic.interrupt();
      await FakeMicAudioSource.pump();

      expect(capture.status, CaptureStatus.interrupted);
      expect(statuses, contains(CaptureStatus.interrupted));
      expect(
        emitted,
        hasLength(1),
        reason: 'ce qui a été capté part quand même',
      );
    });

    test('la reprise repasse le statut à actif', () async {
      await capture.start();
      mic.interrupt();
      await FakeMicAudioSource.pump();
      mic.resume();
      await FakeMicAudioSource.pump();

      expect(capture.status, CaptureStatus.active);
    });

    test(
      "après une interruption, les segments sont datés de l'heure réelle",
      () async {
        await capture.start();
        mic.interrupt();
        await FakeMicAudioSource.pump();

        // L'appel a duré deux minutes : aucune frame n'est arrivée entretemps,
        // le compteur de samples du segmenteur n'a donc pas bougé.
        clock += 120000;
        mic.resume();
        await FakeMicAudioSource.pump();
        await play(AudioFixtures.utterance());

        expect(emitted, hasLength(1));
        expect(
          emitted.single.tStartMs,
          clock,
          reason: 'ré-ancré sur l’horloge, pas sur le début de capture',
        );
      },
    );
  });

  group('micro coupé par l invité', () {
    test('couper relâche le micro sans arrêter le pipeline', () async {
      await capture.start();
      await capture.setMuted(muted: true);

      expect(capture.status, CaptureStatus.muted);
      expect(capture.isStarted, isTrue);
      expect(mic.isRunning, isFalse);
      expect(guard.isHeld, isTrue);
    });

    test('rallumer redémarre le micro et la capture', () async {
      await capture.start();
      await capture.setMuted(muted: true);
      await capture.setMuted(muted: false);

      expect(capture.status, CaptureStatus.active);
      expect(mic.startCount, 2);

      await play(AudioFixtures.utterance());
      expect(emitted, hasLength(1));
    });

    test('couper deux fois de suite ne change rien', () async {
      await capture.start();
      await capture.setMuted(muted: true);
      await capture.setMuted(muted: true);

      expect(mic.stopCount, 1);
    });

    test('couper avant tout démarrage ne fait rien', () async {
      await capture.setMuted(muted: true);

      expect(capture.status, CaptureStatus.idle);
      expect(mic.stopCount, 0);
    });
  });

  group('arrêt', () {
    test('stop() clôt le segment en cours, ferme et relâche', () async {
      await capture.start();
      await play([
        for (var i = 0; i < 10; i++)
          (
            AudioFixtures.frame(AudioFixtures.loudVoice),
            AudioFixtures.speech,
          ),
      ]);
      await capture.stop();

      expect(emitted, hasLength(1), reason: 'la phrase en cours est émise');
      expect(capture.status, CaptureStatus.idle);
      expect(capture.isStarted, isFalse);
      expect(guard.isHeld, isFalse);
    });

    test('stop() sans démarrage préalable ne fait rien', () async {
      await capture.stop();

      expect(guard.releaseCount, 0);
      expect(mic.stopCount, 0);
    });
  });

  group('pannes en cours de flux', () {
    test('une inférence qui échoue arrête la capture et se signale', () async {
      final failures = <Object>[];
      capture.failures.listen(failures.add);
      await capture.start();

      vad
        ..inferenceFailure = const VadInferenceFailure('session ORT perdue')
        ..failAtCall = 1;
      await mic.emit(AudioFixtures.frame(AudioFixtures.loudVoice));

      expect(failures.single, isA<VadInferenceFailure>());
      expect(mic.stopCount, greaterThan(0));
    });
  });
}
