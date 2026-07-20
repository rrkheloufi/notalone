import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:notalone/core/l10n/l10n_keys.dart';
import 'package:notalone/features/onboarding/presentation/onboarding_viewmodel.dart';

/// Premier lancement : une question, un champ, un bouton
/// (cf. cowork/01-cadrage-produit.md §3).
class OnboardingView extends StatefulWidget {
  const OnboardingView({
    required this.viewModel,
    required this.onCompleted,
    super.key,
  });

  final OnboardingViewModel viewModel;

  /// Appelé une fois le prénom enregistré : l'app bascule sur la home.
  final VoidCallback onCompleted;

  @override
  State<OnboardingView> createState() => _OnboardingViewState();
}

class _OnboardingViewState extends State<OnboardingView> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    widget.viewModel.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    await widget.viewModel.saveCommand.execute(_controller.text);
    if (widget.viewModel.isSaved) widget.onCompleted();
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = widget.viewModel;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ListenableBuilder(
            listenable: Listenable.merge([viewModel.saveCommand, _controller]),
            builder: (context, _) {
              final canSubmit =
                  _controller.text.trim().isNotEmpty &&
                  !viewModel.saveCommand.running;
              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    L10nKeys.onboardingTitle.tr(),
                    style: Theme.of(context).textTheme.headlineLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    L10nKeys.onboardingExplanation.tr(),
                    style: Theme.of(context).textTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  TextField(
                    controller: _controller,
                    autofocus: true,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(
                      labelText: L10nKeys.onboardingNameLabel.tr(),
                    ),
                    onSubmitted: (_) => unawaited(_submit()),
                  ),
                  if (viewModel.saveCommand.error) ...[
                    const SizedBox(height: 12),
                    Text(
                      L10nKeys.onboardingSaveError.tr(),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 32),
                  FilledButton(
                    onPressed: canSubmit ? () => unawaited(_submit()) : null,
                    child: Text(L10nKeys.onboardingContinue.tr()),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
