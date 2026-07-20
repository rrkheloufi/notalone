import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notalone/app.dart';
import 'package:notalone/app_dependencies.dart';
import 'package:notalone/core/l10n/app_locales.dart';
import 'package:notalone/features/onboarding/data/shared_preferences_user_profile_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/localized_app.dart';

Future<void> pumpApp(WidgetTester tester) async {
  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: AppLocales.supported,
      path: AppLocales.translationsPath,
      fallbackLocale: AppLocales.fallback,
      assetLoader: frenchLoader,
      child: NotAloneApp(dependencies: AppDependencies()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(initLocalization);

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('premier lancement : l’app demande le prénom', (tester) async {
    await pumpApp(tester);

    expect(find.text("Comment t'appelles-tu ?"), findsOneWidget);
  });

  testWidgets('lancements suivants : la home s’affiche directement', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      SharedPreferencesUserProfileRepository.nameKey: 'Camille',
    });

    await pumpApp(tester);

    expect(find.text('Bonjour Camille'), findsOneWidget);
    expect(find.text('Nouvelle conversation'), findsOneWidget);
    expect(find.text('Rejoindre'), findsOneWidget);
    expect(find.text("Comment t'appelles-tu ?"), findsNothing);
  });

  testWidgets('le prénom saisi au premier lancement mène à la home', (
    tester,
  ) async {
    await pumpApp(tester);

    await tester.enterText(find.byType(TextField), 'Camille');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continuer'));
    await tester.pumpAndSettle();

    expect(find.text('Bonjour Camille'), findsOneWidget);
  });
}
