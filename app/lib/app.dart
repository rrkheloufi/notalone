import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:notalone/app_dependencies.dart';
import 'package:notalone/core/l10n/l10n_keys.dart';
import 'package:notalone/core/theme/app_theme.dart';
import 'package:notalone/features/onboarding/presentation/app_root_viewmodel.dart';
import 'package:notalone/features/onboarding/presentation/onboarding_view.dart';
import 'package:notalone/features/onboarding/presentation/onboarding_viewmodel.dart';
import 'package:notalone/features/session/presentation/home_view.dart';
import 'package:notalone/features/session/presentation/home_viewmodel.dart';

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
      home: _AppRoot(dependencies: dependencies),
    );
  }
}

/// Aiguillage du démarrage : onboarding au premier lancement, home dès que le
/// prénom est connu (cf. cowork/01-cadrage-produit.md §3).
class _AppRoot extends StatefulWidget {
  const _AppRoot({required this.dependencies});

  final AppDependencies dependencies;

  @override
  State<_AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<_AppRoot> {
  late final AppRootViewModel _viewModel = widget.dependencies
      .createAppRootViewModel();

  // Mémorisés : `build` peut se rejouer souvent, et ces ViewModels portent
  // l'état de leur écran (leur vue s'en occupe jusqu'au `dispose`).
  OnboardingViewModel? _onboardingViewModel;
  HomeViewModel? _homeViewModel;

  @override
  void initState() {
    super.initState();
    unawaited(_viewModel.loadCommand.execute());
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, _) {
        if (!_viewModel.isLoaded) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final name = _viewModel.name;
        if (name == null) {
          return OnboardingView(
            viewModel: _onboardingViewModel ??= widget.dependencies
                .createOnboardingViewModel(),
            onCompleted: () => unawaited(_viewModel.loadCommand.execute()),
          );
        }
        return HomeView(
          viewModel: _homeViewModel ??= widget.dependencies
              .createHomeViewModel(name: name),
          destinations: widget.dependencies.homeDestinations,
          microphoneGate: widget.dependencies.microphoneGate,
          cameraGate: widget.dependencies.cameraGate,
        );
      },
    );
  }
}
