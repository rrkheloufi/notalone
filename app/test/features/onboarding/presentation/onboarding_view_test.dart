import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notalone/features/onboarding/domain/onboarding_failure.dart';
import 'package:notalone/features/onboarding/presentation/onboarding_view.dart';
import 'package:notalone/features/onboarding/presentation/onboarding_viewmodel.dart';

import '../../../helpers/fake_user_profile_repository.dart';
import '../../../helpers/localized_app.dart';

void main() {
  setUpAll(initLocalization);

  testWidgets('l’écran explique à quoi sert le prénom', (tester) async {
    await pumpLocalized(
      tester,
      OnboardingView(
        viewModel: OnboardingViewModel(profiles: FakeUserProfileRepository()),
        onCompleted: () {},
      ),
    );

    expect(find.text("Comment t'appelles-tu ?"), findsOneWidget);
    expect(
      find.textContaining("Ton prénom s'affiche à côté de ce que tu dis"),
      findsOneWidget,
    );
  });

  testWidgets('le bouton reste inactif tant que le champ est vide', (
    tester,
  ) async {
    await pumpLocalized(
      tester,
      OnboardingView(
        viewModel: OnboardingViewModel(profiles: FakeUserProfileRepository()),
        onCompleted: () {},
      ),
    );

    final button = find.widgetWithText(FilledButton, 'Continuer');
    expect(tester.widget<FilledButton>(button).onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'Camille');
    await tester.pumpAndSettle();

    expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
  });

  testWidgets('prénom saisi → persisté et onboarding terminé', (tester) async {
    final profiles = FakeUserProfileRepository();
    var completed = 0;
    await pumpLocalized(
      tester,
      OnboardingView(
        viewModel: OnboardingViewModel(profiles: profiles),
        onCompleted: () => completed++,
      ),
    );

    await tester.enterText(find.byType(TextField), 'Camille');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Continuer'));
    await tester.pumpAndSettle();

    expect(profiles.written, ['Camille']);
    expect(completed, 1);
  });

  testWidgets('écriture impossible → message d’erreur, on reste sur l’écran', (
    tester,
  ) async {
    final profiles = FakeUserProfileRepository()
      ..writeFailure = const ProfileStorageFailure('disque plein');
    var completed = 0;
    await pumpLocalized(
      tester,
      OnboardingView(
        viewModel: OnboardingViewModel(profiles: profiles),
        onCompleted: () => completed++,
      ),
    );

    await tester.enterText(find.byType(TextField), 'Camille');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Continuer'));
    await tester.pumpAndSettle();

    expect(
      find.text("Ton prénom n'a pas pu être enregistré. Réessaie."),
      findsOneWidget,
    );
    expect(completed, 0);
  });
}
