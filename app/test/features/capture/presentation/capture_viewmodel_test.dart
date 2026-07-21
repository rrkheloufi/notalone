import 'package:flutter_test/flutter_test.dart';
import 'package:notalone/features/capture/domain/capture_failure.dart';
import 'package:notalone/features/capture/domain/capture_speech_use_case.dart';
import 'package:notalone/features/capture/domain/capture_status.dart';
import 'package:notalone/features/capture/domain/mic_status_reporter.dart';
import 'package:notalone/features/capture/domain/segment_publisher.dart';
import 'package:notalone/features/capture/domain/stt_failure.dart';
import 'package:notalone/features/capture/domain/transcribe_segments_use_case.dart';
import 'package:notalone/features/capture/domain/transcribed_segment.dart';
import 'package:notalone/features/capture/presentation/capture_viewmodel.dart';

import '../../../fixtures/audio_fixtures.dart';
import '../../../helpers/fake_capture_sources.dart';
import '../../../helpers/fake_stt_engine.dart';

void main() {
  late FakeMicAudioSource mic;
  late FakeVadService vad;
  late FakeBackgroundCaptureGuard guard;
  late CaptureSpeechUseCase capture;
  late FakeSttEngine stt;
  late _RecordingPublisher publisher;
  late CaptureViewModel viewModel;

  Future<void> speak({double amplitude = AudioFixtures.loudVoice}) async {
    final script = AudioFixtures.utterance(amplitude: amplitude);
    vad.script([for (final (_, probability) in script) probability]);
    for (final (frame, _) in script) {
      await mic.emit(frame);
    }
  }

  setUp(() {
    mic = FakeMicAudioSource();
    vad = FakeVadService();
    guard = FakeBackgroundCaptureGuard();
    capture = CaptureSpeechUseCase(mic: mic, vad: vad, guard: guard);
    stt = FakeSttEngine();
    publisher = _RecordingPublisher();
    viewModel = CaptureViewModel(
      capture: capture,
      transcribe: TranscribeSegmentsUseCase(engine: stt),
      publisher: publisher,
    );
  });

  tearDown(() async {
    viewModel.dispose();
    await mic.dispose();
  });

  test('à la création, rien ne tourne', () {
    expect(viewModel.isCapturing, isFalse);
    expect(viewModel.status, CaptureStatus.idle);
    expect(viewModel.segments, isEmpty);
  });

  test('startCommand démarre la capture', () async {
    await viewModel.startCommand.execute();

    expect(viewModel.startCommand.completed, isTrue);
    expect(viewModel.isCapturing, isTrue);
    expect(viewModel.status, CaptureStatus.active);
  });

  test('micro refusé → la commande porte la panne', () async {
    mic.failure = const MicPermissionFailure();

    await viewModel.startCommand.execute();

    expect(viewModel.startCommand.error, isTrue);
    expect(
      viewModel.startCommand.result?.failureOrNull,
      isA<MicPermissionFailure>(),
    );
    expect(viewModel.isCapturing, isFalse);
  });

  test('un segment détecté apparaît en tête de liste et notifie', () async {
    var notifications = 0;
    viewModel.addListener(() => notifications++);
    await viewModel.startCommand.execute();

    await speak();

    expect(viewModel.segments, hasLength(1));
    expect(notifications, greaterThan(0));
  });

  test('la liste ne garde que les derniers segments', () async {
    await viewModel.startCommand.execute();

    for (var i = 0; i < CaptureViewModel.maxVisibleSegments + 3; i++) {
      await speak();
    }

    expect(viewModel.segments, hasLength(CaptureViewModel.maxVisibleSegments));
    // Le plus récent d'abord.
    expect(
      viewModel.segments.first.tStartMs,
      greaterThan(viewModel.segments.last.tStartMs),
    );
  });

  test('un segment trop faible ne remonte pas à la vue', () async {
    await viewModel.startCommand.execute();

    await speak(amplitude: AudioFixtures.roomNoise);

    expect(viewModel.segments, isEmpty);
    expect(viewModel.discardedSegments, 1);
  });

  test('une interruption se reflète dans le statut', () async {
    await viewModel.startCommand.execute();

    mic.interrupt();
    await FakeMicAudioSource.pump();

    expect(viewModel.status, CaptureStatus.interrupted);
  });

  test('toggleMuteCommand coupe puis rallume', () async {
    await viewModel.startCommand.execute();

    await viewModel.toggleMuteCommand.execute();
    expect(viewModel.status, CaptureStatus.muted);

    await viewModel.toggleMuteCommand.execute();
    expect(viewModel.status, CaptureStatus.active);
  });

  test('stopCommand arrête la capture', () async {
    await viewModel.startCommand.execute();

    await viewModel.stopCommand.execute();

    expect(viewModel.isCapturing, isFalse);
    expect(viewModel.status, CaptureStatus.idle);
  });

  test('une panne de flux est exposée à la vue', () async {
    await viewModel.startCommand.execute();
    vad
      ..inferenceFailure = const VadInferenceFailure('session ORT perdue')
      ..failAtCall = 1;

    await mic.emit(AudioFixtures.frame(AudioFixtures.loudVoice));

    expect(viewModel.streamFailure, isA<VadInferenceFailure>());
  });

  test('un segment capté est transcrit et son texte devient lisible', () async {
    stt.script(['passe-moi le sel']);
    await viewModel.startCommand.execute();

    await speak();
    await FakeMicAudioSource.pump();

    final segment = viewModel.segments.single;
    expect(
      viewModel.transcriptionOf(segment.segmentId)?.text,
      'passe-moi le sel',
    );
  });

  test('le texte n’est pas encore là au moment où le segment paraît', () async {
    stt.hold();
    await viewModel.startCommand.execute();

    await speak();

    final segment = viewModel.segments.single;
    expect(viewModel.transcriptionOf(segment.segmentId), isNull);

    stt.release();
    await FakeMicAudioSource.pump();

    expect(viewModel.transcriptionOf(segment.segmentId), isNotNull);
  });

  test('startCommand prépare le moteur avant le micro', () async {
    await viewModel.startCommand.execute();

    expect(stt.prepareCount, 1);
    expect(viewModel.sttFailure, isNull);
    expect(viewModel.engine, 'fake');
  });

  test('modèle FR absent : panne affichée mais capture démarrée', () async {
    stt.prepareFailure = const SttModelMissingFailure('fr-FR');

    await viewModel.startCommand.execute();

    expect(viewModel.sttFailure, isA<SttModelMissingFailure>());
    // Le micro tourne quand même : l'invité reste supervisé côté hôte et
    // pourra basculer sur le moteur cloud sans relancer sa session (MVP-14).
    expect(viewModel.isCapturing, isTrue);
    expect(viewModel.startCommand.completed, isTrue);
  });

  test(
    'une panne de transcription est exposée puis effacée au succès',
    () async {
      stt
        ..transcriptionFailure = const SttTranscriptionFailure('moteur occupé')
        ..failAtCall = 1;
      await viewModel.startCommand.execute();

      await speak();
      await FakeMicAudioSource.pump();
      expect(viewModel.sttFailure, isA<SttTranscriptionFailure>());

      stt
        ..transcriptionFailure = null
        ..script(['ça remarche']);
      await speak();
      await FakeMicAudioSource.pump();

      expect(viewModel.sttFailure, isNull);
    },
  );

  test('le texte des segments oubliés est libéré avec eux', () async {
    await viewModel.startCommand.execute();
    await speak();
    await FakeMicAudioSource.pump();
    final oldest = viewModel.segments.single.segmentId;
    expect(viewModel.transcriptionOf(oldest), isNotNull);

    for (var i = 0; i < CaptureViewModel.maxVisibleSegments; i++) {
      await speak();
    }
    await FakeMicAudioSource.pump();

    // Sans nettoyage, la table de textes grossirait pendant tout le repas.
    expect(viewModel.transcriptionOf(oldest), isNull);
  });

  test('une reprise efface la panne affichée', () async {
    await viewModel.startCommand.execute();
    vad
      ..inferenceFailure = const VadInferenceFailure('session ORT perdue')
      ..failAtCall = 1;
    await mic.emit(AudioFixtures.frame(AudioFixtures.loudVoice));
    expect(viewModel.streamFailure, isNotNull);

    mic
      ..interrupt()
      ..resume();
    await FakeMicAudioSource.pump();

    expect(viewModel.streamFailure, isNull);
  });

  group('publication sur le fil (MVP-11)', () {
    test('chaque segment transcrit est publié une fois', () async {
      await viewModel.startCommand.execute();
      await speak();
      await FakeMicAudioSource.pump();

      final segmentId = viewModel.segments.single.segmentId;
      expect(publisher.published, hasLength(1));
      expect(publisher.published.single.segmentId, segmentId);
      expect(publisher.published.single.text, isNotEmpty);
    });

    test("un segment sans texte reconnu n'est pas publié", () async {
      stt.script(['']);
      await viewModel.startCommand.execute();
      await speak();
      await FakeMicAudioSource.pump();

      // Le VAD a bien retenu une prise de parole, mais il n'y avait rien à
      // dire : pas de bulle vide dans le fil du lecteur (MVP-10).
      expect(viewModel.segments, hasLength(1));
      expect(publisher.published, isEmpty);
    });

    test('sans publieur, rien ne quitte le téléphone', () async {
      final solo = CaptureViewModel(
        capture: CaptureSpeechUseCase(mic: mic, vad: vad, guard: guard),
        transcribe: TranscribeSegmentsUseCase(engine: FakeSttEngine()),
      );
      addTearDown(solo.dispose);

      await solo.startCommand.execute();
      await speak();
      await FakeMicAudioSource.pump();

      expect(solo.segments, hasLength(1));
      expect(publisher.published, isEmpty);
    });

    test('dispose libère le publieur', () {
      final ownPublisher = _RecordingPublisher();
      CaptureViewModel(
        capture: CaptureSpeechUseCase(mic: mic, vad: vad, guard: guard),
        transcribe: TranscribeSegmentsUseCase(engine: FakeSttEngine()),
        publisher: ownPublisher,
      ).dispose();

      expect(ownPublisher.disposed, isTrue);
    });
  });

  group('supervision et fin de session (MVP-13)', () {
    test('chaque changement d’état part vers l’hôte', () async {
      final reporter = _RecordingMicStatus();
      final supervised = CaptureViewModel(
        capture: capture,
        transcribe: TranscribeSegmentsUseCase(engine: stt),
        micStatus: reporter,
      );
      addTearDown(supervised.dispose);

      await supervised.startCommand.execute();
      await supervised.toggleMuteCommand.execute();
      await supervised.stopCommand.execute();
      await pumpEventQueue();

      // Poussé à chaque transition : c'est ce qui rend une coupure de micro
      // visible chez l'hôte en moins de 10 s.
      expect(reporter.reported, [
        CaptureStatus.active,
        CaptureStatus.muted,
        CaptureStatus.idle,
      ]);
    });

    test('fin de session : le micro s’arrête et rien n’est gardé', () async {
      await viewModel.startCommand.execute();
      await speak();
      await FakeMicAudioSource.pump();
      expect(viewModel.segments, isNotEmpty);
      final segmentId = viewModel.segments.first.segmentId;

      await viewModel.endSession();

      // Aucune trace sur aucun appareil (critère MVP-13, CLAUDE.md règle 5).
      expect(viewModel.segments, isEmpty);
      expect(viewModel.transcriptionOf(segmentId), isNull);
      expect(viewModel.status, CaptureStatus.idle);
      expect(viewModel.isCapturing, isFalse);
    });

    test('dispose libère aussi le rapporteur', () {
      final reporter = _RecordingMicStatus();
      CaptureViewModel(
        capture: CaptureSpeechUseCase(
          mic: FakeMicAudioSource(),
          vad: FakeVadService(),
          guard: FakeBackgroundCaptureGuard(),
        ),
        transcribe: TranscribeSegmentsUseCase(engine: FakeSttEngine()),
        micStatus: reporter,
      ).dispose();

      expect(reporter.isDisposed, isTrue);
    });
  });
}

/// L'état du micro tel que l'hôte le recevrait, retenu au lieu d'être envoyé.
class _RecordingMicStatus implements MicStatusReporter {
  final List<CaptureStatus> reported = [];
  bool isDisposed = false;

  @override
  void report(CaptureStatus status) => reported.add(status);

  @override
  Future<void> dispose() async => isDisposed = true;
}

/// Ce que l'invité met sur le fil, retenu au lieu d'être envoyé.
class _RecordingPublisher implements SegmentPublisher {
  final List<TranscribedSegment> published = [];
  bool disposed = false;

  @override
  void publish(TranscribedSegment segment) => published.add(segment);

  @override
  Future<void> dispose() async => disposed = true;
}
