import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notalone/core/l10n/app_locales.dart';
import 'package:notalone/core/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Traductions FR lues une fois sur disque, servies ensuite sans I/O.
///
/// easy_localization charge normalement ses fichiers depuis le bundle : cette
/// lecture asynchrone ne se résout pas sous l'horloge simulée des widget tests
/// dès le second test d'un fichier, qui montait alors un écran vide. On lui
/// fournit donc le **vrai** `fr.json` — les tests continuent de vérifier les
/// chaînes réellement livrées.
class _PreloadedFrenchLoader extends AssetLoader {
  const _PreloadedFrenchLoader(this._translations);

  final Map<String, dynamic> _translations;

  @override
  Future<Map<String, dynamic>?> load(String path, Locale locale) async =>
      _translations;
}

late _PreloadedFrenchLoader _loader;

/// À appeler en `setUpAll` de tout fichier de widget tests.
Future<void> initLocalization() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final raw = File('${AppLocales.translationsPath}/fr.json').readAsStringSync();
  _loader = _PreloadedFrenchLoader(
    jsonDecode(raw) as Map<String, dynamic>,
  );
  await EasyLocalization.ensureInitialized();
}

/// Le même chargeur, pour les tests qui montent l'app entière (et donc leur
/// propre `EasyLocalization`) au lieu d'un écran isolé.
AssetLoader get frenchLoader => _loader;

/// Gabarit de téléphone plutôt que les 800×600 par défaut de flutter_test :
/// nos écrans sont faits pour un mobile tenu à la verticale, et une fenêtre
/// plus large les rendrait dans une disposition que personne ne verra.
const Size phoneSize = Size(400, 900);

/// Monte [child] dans une app localisée en français, sur un gabarit mobile.
///
/// [brightness] nul laisse le thème par défaut de `MaterialApp` : c'est ce que
/// veulent les tests de comportement. Les goldens, eux, le fixent pour capturer
/// le vrai thème de l'app dans les deux modes.
Future<void> pumpLocalized(
  WidgetTester tester,
  Widget child, {
  Brightness? brightness,
}) async {
  tester.view
    ..physicalSize = phoneSize
    ..devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: AppLocales.supported,
      path: AppLocales.translationsPath,
      fallbackLocale: AppLocales.fallback,
      assetLoader: _loader,
      child: Builder(
        builder: (context) => MaterialApp(
          localizationsDelegates: context.localizationDelegates,
          supportedLocales: context.supportedLocales,
          locale: context.locale,
          theme: brightness == null
              ? null
              : (brightness == Brightness.dark
                    ? AppTheme.dark
                    : AppTheme.light),
          home: child,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
