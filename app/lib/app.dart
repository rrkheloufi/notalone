import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:notalone/app_dependencies.dart';
import 'package:notalone/core/l10n/l10n_keys.dart';
import 'package:notalone/core/theme/app_theme.dart';
import 'package:notalone/features/capture/presentation/vad_debug_view.dart';
import 'package:notalone/features/session/presentation/lan_guest_debug_view.dart';
import 'package:notalone/features/session/presentation/lan_host_debug_view.dart';

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
      home: _PlaceholderHomeView(dependencies: dependencies),
    );
  }
}

// Écran provisoire : la vraie home (2 boutons) arrive en MVP-07.
class _PlaceholderHomeView extends StatelessWidget {
  const _PlaceholderHomeView({required this.dependencies});

  final AppDependencies dependencies;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              L10nKeys.homePlaceholder.tr(),
              style: Theme.of(context).textTheme.headlineLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            // Accès aux spikes MVP-02/03, retirés avec eux.
            OutlinedButton(
              onPressed: () => unawaited(
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => VadDebugView(
                      viewModel: dependencies.createVadDebugViewModel(),
                    ),
                  ),
                ),
              ),
              child: Text(L10nKeys.vadDebugOpen.tr()),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => unawaited(
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => LanHostDebugView(
                      viewModel: dependencies.createLanHostDebugViewModel(),
                    ),
                  ),
                ),
              ),
              child: Text(L10nKeys.lanDebugOpenHost.tr()),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => unawaited(
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => LanGuestDebugView(
                      viewModel: dependencies.createLanGuestDebugViewModel(),
                    ),
                  ),
                ),
              ),
              child: Text(L10nKeys.lanDebugOpenGuest.tr()),
            ),
          ],
        ),
      ),
    );
  }
}
