import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notalone/app.dart';
import 'package:notalone/app_dependencies.dart';
import 'package:notalone/core/l10n/app_locales.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('l’app démarre et affiche l’écran provisoire en français',
      (tester) async {
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: AppLocales.supported,
        path: AppLocales.translationsPath,
        fallbackLocale: AppLocales.fallback,
        child: const NotAloneApp(dependencies: AppDependencies()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Bienvenue dans NotAlone'), findsOneWidget);
  });
}
