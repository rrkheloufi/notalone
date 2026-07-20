import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notalone/features/onboarding/domain/onboarding_failure.dart';
import 'package:notalone/features/settings/presentation/settings_view.dart';
import 'package:notalone/features/settings/presentation/settings_viewmodel.dart';

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
        ),
      ),
    );

    expect(find.widgetWithText(TextField, 'Camille'), findsOneWidget);
  });

  testWidgets('le prénom modifié est enregistré et confirmé', (tester) async {
    final profiles = FakeUserProfileRepository(name: 'Camille');
    await pumpLocalized(
      tester,
      SettingsView(viewModel: SettingsViewModel(profiles: profiles)),
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
      SettingsView(viewModel: SettingsViewModel(profiles: profiles)),
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
      SettingsView(viewModel: SettingsViewModel(profiles: profiles)),
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
}
