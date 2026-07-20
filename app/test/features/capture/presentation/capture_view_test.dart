import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notalone/features/capture/domain/capture_failure.dart';
import 'package:notalone/features/capture/domain/capture_speech_use_case.dart';
import 'package:notalone/features/capture/domain/stt_failure.dart';
import 'package:notalone/features/capture/domain/transcribe_segments_use_case.dart';
import 'package:notalone/features/capture/presentation/capture_view.dart';
import 'package:notalone/features/capture/presentation/capture_viewmodel.dart';

import '../../../fixtures/audio_fixtures.dart';
import '../../../helpers/fake_capture_sources.dart';
import '../../../helpers/fake_stt_engine.dart';
import '../../../helpers/localized_app.dart';

void main() {
  late FakeMicAudioSource mic;
  late FakeVadService vad;
  late FakeBackgroundCaptureGuard guard;
  late FakeSttEngine stt;
  late CaptureViewModel viewModel;

  setUpAll(initLocalization);

  setUp(() {
    mic = FakeMicAudioSource();
    vad = FakeVadService();
    guard = FakeBackgroundCaptureGuard();
    stt = FakeSttEngine();
    viewModel = CaptureViewModel(
      capture: CaptureSpeechUseCase(mic: mic, vad: vad, guard: guard),
      transcribe: TranscribeSegmentsUseCase(engine: stt),
    );
  });

  tearDown(() async => mic.dispose());

  /// Tape un bouton dont l'action annule une souscription (couper le micro,
  /// arrêter la capture). Sous l'horloge simulée de `testWidgets`, la chaîne
  /// asynchrone qui suit un `StreamSubscription.cancel()` ne progresse plus —
  /// `runAsync` la déroule dans la vraie zone avant qu'on repeigne.
  Future<void> tapAndRun(WidgetTester tester, String label) async {
    await tester.runAsync(() async {
      await tester.tap(find.text(label));
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();
  }

  Future<void> speak(WidgetTester tester) async {
    final script = AudioFixtures.utterance();
    vad.script([for (final (_, probability) in script) probability]);
    for (final (frame, _) in script) {
      mic.emitSync(frame);
    }
    await tester.pumpAndSettle();
  }

  testWidgets('au repos : micro arrêté et invitation à démarrer', (
    tester,
  ) async {
    await pumpLocalized(tester, CaptureView(viewModel: viewModel));

    expect(find.text('Micro arrêté'), findsOneWidget);
    expect(find.text('Démarrer la capture'), findsOneWidget);
    expect(find.text('Aucune prise de parole pour l’instant'), findsOneWidget);
  });

  testWidgets('démarrer affiche le micro actif et les contrôles', (
    tester,
  ) async {
    await pumpLocalized(tester, CaptureView(viewModel: viewModel));

    await tester.tap(find.text('Démarrer la capture'));
    await tester.pumpAndSettle();

    expect(find.text('Micro actif'), findsOneWidget);
    expect(find.text('Couper le micro'), findsOneWidget);
    expect(find.text('Arrêter'), findsOneWidget);
  });

  testWidgets('une prise de parole apparaît dans la liste', (tester) async {
    await pumpLocalized(tester, CaptureView(viewModel: viewModel));
    await tester.tap(find.text('Démarrer la capture'));
    await tester.pumpAndSettle();

    await speak(tester);

    expect(find.text('Aucune prise de parole pour l’instant'), findsNothing);
    expect(find.byType(ListTile), findsOneWidget);
  });

  testWidgets('une interruption est annoncée à l invité', (tester) async {
    await pumpLocalized(tester, CaptureView(viewModel: viewModel));
    await tester.tap(find.text('Démarrer la capture'));
    await tester.pumpAndSettle();

    mic.interrupt();
    await tester.pumpAndSettle();

    expect(
      find.text('Micro interrompu — reprise automatique'),
      findsOneWidget,
    );
  });

  testWidgets('couper le micro le dit sans arrêter la capture', (tester) async {
    await pumpLocalized(tester, CaptureView(viewModel: viewModel));
    await tester.tap(find.text('Démarrer la capture'));
    await tester.pumpAndSettle();

    await tapAndRun(tester, 'Couper le micro');

    expect(find.text('Micro coupé'), findsOneWidget);
    expect(find.text('Rallumer le micro'), findsOneWidget);
    expect(find.text('Arrêter'), findsOneWidget);
  });

  testWidgets('le texte transcrit s’affiche à la place de l’attente', (
    tester,
  ) async {
    stt
      ..script(['passe-moi le sel'])
      ..hold();
    await pumpLocalized(tester, CaptureView(viewModel: viewModel));
    await tester.tap(find.text('Démarrer la capture'));
    await tester.pumpAndSettle();

    await speak(tester);
    expect(find.text('transcription en cours…'), findsOneWidget);

    await tester.runAsync(() async {
      stt.release();
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();

    expect(find.text('transcription en cours…'), findsNothing);
    expect(find.text('passe-moi le sel'), findsOneWidget);
  });

  testWidgets('le moteur retenu est affiché pendant la capture', (
    tester,
  ) async {
    await pumpLocalized(tester, CaptureView(viewModel: viewModel));

    expect(find.text('Moteur : fake'), findsNothing);

    await tester.tap(find.text('Démarrer la capture'));
    await tester.pumpAndSettle();

    expect(find.text('Moteur : fake'), findsOneWidget);
  });

  testWidgets('un modèle FR absent est expliqué sans bloquer la capture', (
    tester,
  ) async {
    stt.prepareFailure = const SttModelMissingFailure('fr-FR');
    await pumpLocalized(tester, CaptureView(viewModel: viewModel));

    await tester.tap(find.text('Démarrer la capture'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('modèle de reconnaissance vocale française'),
      findsOneWidget,
    );
    expect(find.text('Micro actif'), findsOneWidget);
  });

  testWidgets('un téléphone qui refuse notre audio est expliqué', (
    tester,
  ) async {
    stt.prepareFailure = const SttAudioSourceUnsupportedFailure('code 3');
    await pumpLocalized(tester, CaptureView(viewModel: viewModel));

    await tester.tap(find.text('Démarrer la capture'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('refuse l’audio de l’app'),
      findsOneWidget,
    );
  });

  testWidgets('un refus de permission est expliqué', (tester) async {
    mic.failure = const MicPermissionFailure();
    await pumpLocalized(tester, CaptureView(viewModel: viewModel));

    await tester.tap(find.text('Démarrer la capture'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Accès micro refusé : autorise NotAlone dans les réglages système.',
      ),
      findsOneWidget,
    );
  });
}
