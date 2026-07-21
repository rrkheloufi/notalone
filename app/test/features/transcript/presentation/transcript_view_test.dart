import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notalone/features/transcript/domain/speaker.dart';
import 'package:notalone/features/transcript/domain/transcript_text_scale.dart';
import 'package:notalone/features/transcript/presentation/transcript_view.dart';
import 'package:notalone/features/transcript/presentation/transcript_viewmodel.dart';

import '../../../helpers/fake_transcript_sources.dart';
import '../../../helpers/localized_app.dart';

const Speaker _papa = Speaker(id: 'p1', name: 'Papa', colorIndex: 0);
const Speaker _lea = Speaker(id: 'p2', name: 'Léa', colorIndex: 1);

void main() {
  setUpAll(initLocalization);

  late FakeTranscriptBinding binding;
  late FakeSpeakerDirectory directory;
  late FakeTranscriptPreferences preferences;
  late FakeScreenWakeLock wakeLock;
  late TranscriptViewModel viewModel;

  setUp(() {
    binding = FakeTranscriptBinding();
    directory = FakeSpeakerDirectory([_papa, _lea]);
    preferences = FakeTranscriptPreferences();
    wakeLock = FakeScreenWakeLock();
    viewModel = TranscriptViewModel(
      binding: binding,
      speakers: directory,
      preferences: preferences,
      wakeLock: wakeLock,
    );
  });

  tearDown(() => viewModel.dispose());

  Future<void> pumpView(WidgetTester tester, {String? qrData}) =>
      pumpLocalized(
        tester,
        TranscriptView(
          viewModel: viewModel,
          sessionName: 'Conversation de Rayan',
          qrData: qrData,
        ),
      );

  testWidgets('annonce le fil vide plutôt qu’un écran nu', (tester) async {
    await pumpView(tester);

    expect(find.text("Personne n'a encore parlé"), findsOneWidget);
  });

  testWidgets('allume le verrou d’écran à l’ouverture', (tester) async {
    await pumpView(tester);

    expect(wakeLock.isEnabled, isTrue);
  });

  testWidgets('affiche prénom et phrase de chaque prise de parole', (
    tester,
  ) async {
    await pumpView(tester);

    await binding.emit(entry(participantId: 'p1', text: 'Passe le sel'));
    await binding.emit(entry(participantId: 'p2', text: 'Oui, deux secondes'));
    await tester.pumpAndSettle();

    expect(find.text('Papa'), findsOneWidget);
    expect(find.text('Passe le sel'), findsOneWidget);
    expect(find.text('Léa'), findsOneWidget);
    expect(find.text('Oui, deux secondes'), findsOneWidget);
  });

  testWidgets('la phrase la plus récente est la plus basse', (tester) async {
    await pumpView(tester);

    await binding.emit(entry(participantId: 'p1', text: 'la première'));
    await binding.emit(entry(participantId: 'p2', text: 'la dernière'));
    await tester.pumpAndSettle();

    final first = tester.getCenter(find.text('la première'));
    final last = tester.getCenter(find.text('la dernière'));
    expect(last.dy, greaterThan(first.dy));
  });

  testWidgets('un appui sur un prénom isole ce locuteur, un autre le rend', (
    tester,
  ) async {
    await pumpView(tester);
    await binding.emit(entry(participantId: 'p1', text: 'papa parle'));
    await binding.emit(entry(participantId: 'p2', text: 'léa parle'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Papa'));
    await tester.pumpAndSettle();

    expect(find.text('papa parle'), findsOneWidget);
    expect(find.text('léa parle'), findsNothing);
    expect(find.text('On ne voit que Papa'), findsOneWidget);

    // Deuxième geste : le bandeau de filtre le désactive.
    await tester.tap(find.text('Revoir tout le monde'));
    await tester.pumpAndSettle();

    expect(find.text('léa parle'), findsOneWidget);
    expect(find.text('On ne voit que Papa'), findsNothing);
  });

  testWidgets('un filtre sans phrase le dit avec le bon prénom', (
    tester,
  ) async {
    await pumpView(tester);
    await binding.emit(entry(participantId: 'p1', text: 'papa parle'));
    await tester.pumpAndSettle();

    viewModel.toggleSpeakerFilter('p2');
    await tester.pumpAndSettle();

    expect(find.text("Léa n'a encore rien dit"), findsOneWidget);
  });

  testWidgets('les boutons de taille agrandissent et réduisent le texte', (
    tester,
  ) async {
    preferences.stored = TranscriptTextScale.large;
    await pumpView(tester);
    await binding.emit(entry(participantId: 'p1', text: 'une phrase'));
    await tester.pumpAndSettle();

    double bodySize() =>
        tester.widget<Text>(find.text('une phrase')).style!.fontSize!;

    expect(bodySize(), TranscriptTextScale.large.bodySize);

    await tester.tap(find.byIcon(Icons.text_increase));
    await tester.pumpAndSettle();
    expect(bodySize(), TranscriptTextScale.extraLarge.bodySize);

    await tester.tap(find.byIcon(Icons.text_decrease));
    await tester.pumpAndSettle();
    expect(bodySize(), TranscriptTextScale.large.bodySize);
  });

  testWidgets('les boutons de taille se grisent aux extrémités', (
    tester,
  ) async {
    preferences.stored = TranscriptTextScale.values.last;
    await pumpView(tester);

    expect(
      tester.widget<IconButton>(
        find.ancestor(
          of: find.byIcon(Icons.text_increase),
          matching: find.byType(IconButton),
        ),
      ).onPressed,
      isNull,
    );
  });

  testWidgets('le badge n’apparaît que si le lecteur a remonté le fil', (
    tester,
  ) async {
    await pumpView(tester);
    await binding.emit(entry(participantId: 'p1', text: 'une phrase'));
    await tester.pumpAndSettle();

    expect(find.textContaining('nouveau'), findsNothing);

    viewModel.setFollowing(following: false);
    await binding.emit(entry(participantId: 'p2', text: 'une autre'));
    await tester.pumpAndSettle();

    expect(find.text('1 nouveau message'), findsOneWidget);

    await binding.emit(entry(participantId: 'p2', text: 'et encore une'));
    await tester.pumpAndSettle();

    expect(find.text('2 nouveaux messages'), findsOneWidget);
  });

  testWidgets('appuyer sur le badge ramène au plus récent', (tester) async {
    await pumpView(tester);
    for (var i = 0; i < 30; i++) {
      await binding.emit(entry(participantId: 'p1', text: 'phrase $i'));
    }
    await tester.pumpAndSettle();

    viewModel.setFollowing(following: false);
    await binding.emit(entry(participantId: 'p2', text: 'la toute dernière'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('1 nouveau message'));
    await tester.pumpAndSettle();

    expect(viewModel.isFollowing, isTrue);
    expect(find.textContaining('nouveau'), findsNothing);
    expect(find.text('la toute dernière'), findsOneWidget);
  });

  testWidgets('remonter le fil suspend le suivi, sans rien déplacer', (
    tester,
  ) async {
    await pumpView(tester);
    for (var i = 0; i < 40; i++) {
      await binding.emit(entry(participantId: 'p1', text: 'phrase $i'));
    }
    await tester.pumpAndSettle();
    expect(viewModel.isFollowing, isTrue);

    // `reverse: true` : faire glisser vers le bas remonte dans l'historique.
    await tester.drag(find.byType(ListView), const Offset(0, 600));
    await tester.pumpAndSettle();

    expect(viewModel.isFollowing, isFalse);
  });

  testWidgets('le QR est rappelable sans quitter le fil', (tester) async {
    await pumpView(tester, qrData: 'notalone://demo');

    await tester.tap(find.byIcon(Icons.qr_code_2));
    await tester.pumpAndSettle();

    expect(find.text("Faire rejoindre quelqu'un"), findsOneWidget);
  });

  testWidgets('sans QR, le bouton n’existe pas', (tester) async {
    await pumpView(tester);

    expect(find.byIcon(Icons.qr_code_2), findsNothing);
  });

  testWidgets('une entrée tardive est signalée sans être déplacée', (
    tester,
  ) async {
    await pumpView(tester);

    await binding.emit(
      entry(participantId: 'p1', text: 'déjà lu', tStartMs: 5000),
    );
    await binding.emit(
      entry(
        participantId: 'p2',
        text: 'en retard',
        tStartMs: 1000,
        isLate: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.schedule), findsOneWidget);
    final read = tester.getCenter(find.text('déjà lu'));
    final late = tester.getCenter(find.text('en retard'));
    expect(late.dy, greaterThan(read.dy));
  });

  testWidgets('quitter l’écran ne ferme pas le fil', (tester) async {
    await pumpView(tester);

    // La vue est jetée ; le ViewModel appartient au salon et doit survivre —
    // le lecteur revient au QR puis rouvre le fil sans rien perdre.
    await pumpLocalized(tester, const SizedBox());

    expect(binding.isDisposed, isFalse);
    await binding.emit(entry(participantId: 'p1', text: 'pendant l’absence'));
    expect(viewModel.messages, hasLength(1));
  });

  group('bandeau de supervision injecté (MVP-13)', () {
    testWidgets('posé en haut du fil quand le salon en fournit un', (
      tester,
    ) async {
      // Injecté, jamais importé : c'est ce qui laisse `transcript/` ignorer
      // `session/` (CLAUDE.md règle 3).
      await pumpLocalized(
        tester,
        TranscriptView(
          viewModel: viewModel,
          supervisionBanner: const Text('le micro de Paul est coupé'),
        ),
      );

      expect(find.text('le micro de Paul est coupé'), findsOneWidget);
    });

    testWidgets('sans bandeau, le fil reste celui de MVP-12', (tester) async {
      await pumpLocalized(tester, TranscriptView(viewModel: viewModel));

      expect(find.text("Personne n'a encore parlé"), findsOneWidget);
    });
  });
}
