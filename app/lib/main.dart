import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:notalone/app.dart';
import 'package:notalone/app_dependencies.dart';
import 'package:notalone/core/l10n/app_locales.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();
  final dependencies = AppDependencies();
  runApp(
    EasyLocalization(
      supportedLocales: AppLocales.supported,
      path: AppLocales.translationsPath,
      fallbackLocale: AppLocales.fallback,
      child: NotAloneApp(dependencies: dependencies),
    ),
  );
}
