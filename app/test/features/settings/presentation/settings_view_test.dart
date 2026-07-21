import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notalone/features/onboarding/domain/onboarding_failure.dart';
import 'package:notalone/features/settings/presentation/settings_view.dart';
import 'package:notalone/features/settings/presentation/settings_viewmodel.dart';
import 'package:notalone/features/transcript/domain/transcript_text_scale.dart';

import '../../../helpers/fake_transcript_sources.dart';
import '../../../helpers/fake_user_profile_repository.dart';
import '../../../helpers/localized_app.dart';

void main() {
  setUpAll(initLocalization);

  testWidgets('les réglages ouvrent sur le prénom courant', (tester) async {
    await pumpLocalized(
      tester,
      SettingsView(
        viewModel: SettingsViewModel(
          profiles: FakeUserProfileRepository(name: 'Camille'),
          preferences: FakeTranscriptPreferences(),
        ),
      ),
    );

    expect(find.widgetWithText(TextField, 'Camille'), findsOneWidget);
  });

  testWidgets('le prénom modifié est enregistré et confirmé', (tester) async {
    final profiles = FakeUserProfileRepository(name: 'Camille');
    await pumpLocalized(
      tester,
      SettingsView(viewModel: SettingsViewModel(
        profiles: profiles,
        preferences: FakeTranscriptPreferences(),
      )),
    );

    await tester.enterText(find.byType(TextField), 'Paul');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Enregistrer'));
    await tester.pumpAndSettle();

    expect(profiles.written, ['Paul']);
    expect(find.text('Prénom enregistré'), findsOneWidget);
  });

  testWidgets('champ vidé → enregistrement impossible', (tester) async {
    final profiles = FakeUserProfileRepository(name: 'Camille');
    await pumpLocalized(
      tester,
      SettingsView(viewModel: SettingsViewModel(
        profiles: profiles,
        preferences: FakeTranscriptPreferences(),
      )),
    );

    await tester.enterText(find.byType(TextField), '   ');
    await tester.pumpAndSettle();

    final button = find.widgetWithText(FilledButton, 'Enregistrer');
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    expect(profiles.written, isEmpty);
  });

  testWidgets('écriture impossible → message d’erreur', (tester) async {
    final profiles = FakeUserProfileRepository(name: 'Camille')
      ..writeFailure = const ProfileStorageFailure('disque plein');
    await pumpLocalized(
      tester,
      SettingsView(viewModel: SettingsViewModel(
        profiles: profiles,
        preferences: FakeTranscriptPreferences(),
      )),
    );

    await tester.enterText(find.byType(TextField), 'Paul');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Enregistrer'));
    await tester.pumpAndSettle();

    expect(
      find.text("Ton prénom n'a pas pu être enregistré. Réessaie."),
      findsOneWidget,
    );
  });

  group('taille du texte (MVP-13)', () {
    testWidgets('les trois tailles sont proposées, la persistée cochée', (
      tester,
    ) async {
      await pumpLocalized(
        tester,
        SettingsView(
          viewModel: SettingsViewModel(
            profiles: FakeUserProfileRepository(name: 'Camille'),
            preferences: FakeTranscriptPreferences(
              stored: TranscriptTextScale.maximum,
            ),
          ),
        ),
      );

      expect(find.text('Taille du texte'), findsOneWidget);
      final segmented = tester.widget<SegmentedButton<TranscriptTextScale>>(
        find.byType(SegmentedButton<TranscriptTextScale>),
      );
      expect(segmented.selected, {TranscriptTextScale.maximum});
    });

    testWidgets('changer de taille l’enregistre et grossit l’aperçu', (
      tester,
    ) async {
      // L'aperçu est rendu au corps réel : trois libellés ne diraient rien à
      // qui doit lire à 60 cm, une phrase à la vraie taille le dit tout de
      // suite.
      final preferences = FakeTranscriptPreferences(
        stored: TranscriptTextScale.large,
      );
      await pumpLocalized(
        tester,
        SettingsView(
          viewModel: SettingsViewModel(
            profiles: FakeUserProfileRepository(name: 'Camille'),
            preferences: preferences,
          ),
        ),
      );
      double previewSize() => tester
          .widget<Text>(
            find.text('Voilà à quoi ressemblera la conversation.'),
          )
          .style!
          .fontSize!;
      final before = previewSize();

      await tester.tap(find.text('Très grande'));
      await tester.pumpAndSettle();

      expect(preferences.written, [TranscriptTextScale.maximum]);
      expect(previewSize(), greaterThan(before));
      expect(previewSize(), TranscriptTextScale.maximum.bodySize);
    });
  });
}
