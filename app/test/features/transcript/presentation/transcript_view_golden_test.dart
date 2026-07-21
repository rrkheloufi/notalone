import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notalone/features/transcript/domain/speaker.dart';
import 'package:notalone/features/transcript/domain/transcript_text_scale.dart';
import 'package:notalone/features/transcript/presentation/transcript_view.dart';
import 'package:notalone/features/transcript/presentation/transcript_viewmodel.dart';

import '../../../helpers/fake_transcript_sources.dart';
import '../../../helpers/localized_app.dart';

/// Goldens du fil aux trois tailles, en clair et en sombre.
///
/// Ce qu'ils gardent : qu'agrandir le texte agrandisse vraiment la phrase sans
/// écraser la mise en page ni faire déborder les bulles — c'est le critère
/// « lisible à 60 cm en taille max », et c'est le genre de régression qu'un
/// `expect` sur une taille de police ne voit pas passer.
///
/// Les captures utilisent la police de test de Flutter (des rectangles) : elles
/// figent la **géométrie**, pas le dessin des lettres, et restent donc stables
/// d'une machine à l'autre.
const List<Speaker> _table = [
  Speaker(id: 'p1', name: 'Papa', colorIndex: 0),
  Speaker(id: 'p2', name: 'Léa', colorIndex: 1),
  Speaker(id: 'p3', name: 'Rayan', colorIndex: 2),
];

void main() {
  setUpAll(initLocalization);

  late FakeTranscriptBinding binding;
  late TranscriptViewModel viewModel;

  Future<void> buildThread({
    required WidgetTester tester,
    required TranscriptTextScale scale,
    required Brightness brightness,
  }) async {
    binding = FakeTranscriptBinding();
    viewModel = TranscriptViewModel(
      binding: binding,
      speakers: FakeSpeakerDirectory(_table),
      preferences: FakeTranscriptPreferences(stored: scale),
      wakeLock: FakeScreenWakeLock(),
    );
    addTearDown(viewModel.dispose);

    await pumpLocalized(
      tester,
      TranscriptView(
        viewModel: viewModel,
        sessionName: 'Conversation de Rayan',
        qrData: 'notalone://demo',
      ),
      brightness: brightness,
    );

    // Un échange court mais représentatif : une phrase longue qui doit passer
    // à la ligne, une courte, et une tardive avec son repère.
    await binding.emit(
      entry(participantId: 'p1', text: 'Passe-moi le sel', tStartMs: 1000),
    );
    await binding.emit(
      entry(
        participantId: 'p2',
        text: 'Oui deux secondes, je finis de servir tout le monde',
        tStartMs: 2000,
      ),
    );
    await binding.emit(
      entry(
        participantId: 'p3',
        text: 'On mange très bien ici',
        tStartMs: 1500,
        isLate: true,
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final scale in TranscriptTextScale.values) {
    testWidgets('fil en taille ${scale.name}, thème clair', (tester) async {
      await buildThread(
        tester: tester,
        scale: scale,
        brightness: Brightness.light,
      );

      await expectLater(
        find.byType(TranscriptView),
        matchesGoldenFile('goldens/transcript_${scale.name}_light.png'),
      );
    });

    testWidgets('fil en taille ${scale.name}, thème sombre', (tester) async {
      await buildThread(
        tester: tester,
        scale: scale,
        brightness: Brightness.dark,
      );

      await expectLater(
        find.byType(TranscriptView),
        matchesGoldenFile('goldens/transcript_${scale.name}_dark.png'),
      );
    });
  }
}
