import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:notalone/app_dependencies.dart';
import 'package:notalone/core/l10n/l10n_keys.dart';
import 'package:notalone/core/theme/app_theme.dart';

class NotAloneApp extends StatelessWidget {
  const NotAloneApp({required this.dependencies, super.key});

  final AppDependencies dependencies;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (context) => L10nKeys.appTitle.tr(),
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      home: const _PlaceholderHomeView(),
    );
  }
}

// Écran provisoire : la vraie home (2 boutons) arrive en MVP-07.
class _PlaceholderHomeView extends StatelessWidget {
  const _PlaceholderHomeView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Text(
          L10nKeys.homePlaceholder.tr(),
          style: Theme.of(context).textTheme.headlineLarge,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
