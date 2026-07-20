import 'package:flutter_test/flutter_test.dart';
import 'package:notalone/features/capture/domain/capture_failure.dart';
import 'package:notalone/features/capture/domain/capture_speech_use_case.dart';
import 'package:notalone/features/capture/domain/capture_status.dart';
import 'package:notalone/features/capture/presentation/capture_viewmodel.dart';

import '../../../fixtures/audio_fixtures.dart';
import '../../../helpers/fake_capture_sources.dart';

void main() {
  late FakeMicAudioSource mic;
  late FakeVadService vad;
  late FakeBackgroundCaptureGuard guard;
  late CaptureSpeechUseCase capture;
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
    viewModel = CaptureViewModel(capture: capture);
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
}
