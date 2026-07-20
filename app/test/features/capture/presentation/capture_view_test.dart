import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notalone/features/capture/domain/capture_failure.dart';
import 'package:notalone/features/capture/domain/capture_speech_use_case.dart';
import 'package:notalone/features/capture/presentation/capture_view.dart';
import 'package:notalone/features/capture/presentation/capture_viewmodel.dart';

import '../../../fixtures/audio_fixtures.dart';
import '../../../helpers/fake_capture_sources.dart';
import '../../../helpers/localized_app.dart';

void main() {
  late FakeMicAudioSource mic;
  late FakeVadService vad;
  late FakeBackgroundCaptureGuard guard;
  late CaptureViewModel viewModel;

  setUpAll(initLocalization);

  setUp(() {
    mic = FakeMicAudioSource();
    vad = FakeVadService();
    guard = FakeBackgroundCaptureGuard();
    viewModel = CaptureViewModel(
      capture: CaptureSpeechUseCase(mic: mic, vad: vad, guard: guard),
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
