import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:notalone/app_dependencies.dart';
import 'package:notalone/core/l10n/l10n_keys.dart';
import 'package:notalone/core/theme/app_theme.dart';
import 'package:notalone/features/capture/presentation/vad_debug_view.dart';
import 'package:notalone/features/session/presentation/host_lobby_view.dart';
import 'package:notalone/features/session/presentation/join_view.dart';

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

// Écran provisoire : la vraie home (prénom, permissions) arrive en MVP-07.
// Les deux boutons sont déjà ceux du doc 01 §3.
class _PlaceholderHomeView extends StatelessWidget {
  const _PlaceholderHomeView({required this.dependencies});

  final AppDependencies dependencies;

  void _openHostLobby(BuildContext context) {
    const name = AppDependencies.provisionalName;
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => HostLobbyView(
            viewModel: dependencies.createHostLobbyViewModel(
              hostName: name,
              sessionName: L10nKeys.hostLobbySessionName.tr(
                namedArgs: {'name': name},
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _openJoin(BuildContext context) {
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => JoinView(
            viewModel: dependencies.createJoinViewModel(
              initialName: AppDependencies.provisionalName,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  L10nKeys.homePlaceholder.tr(),
                  style: Theme.of(context).textTheme.headlineLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                FilledButton.icon(
                  onPressed: () => _openHostLobby(context),
                  icon: const Icon(Icons.qr_code_2),
                  label: Text(L10nKeys.homeNewConversation.tr()),
                ),
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: () => _openJoin(context),
                  icon: const Icon(Icons.qr_code_scanner),
                  label: Text(L10nKeys.homeJoin.tr()),
                ),
                const SizedBox(height: 32),
                // Accès au spike MVP-02, retiré avec lui en MVP-08.
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
