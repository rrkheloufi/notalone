import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:notalone/core/l10n/l10n_keys.dart';
import 'package:notalone/features/settings/presentation/settings_viewmodel.dart';

/// Réglages : le prénom, modifiable à tout moment (doc 01 §3).
class SettingsView extends StatefulWidget {
  const SettingsView({required this.viewModel, super.key});

  final SettingsViewModel viewModel;

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  final TextEditingController _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    await widget.viewModel.loadCommand.execute();
    if (mounted) _controller.text = widget.viewModel.name;
  }

  @override
  void dispose() {
    _controller.dispose();
    widget.viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = widget.viewModel;
    return Scaffold(
      appBar: AppBar(title: Text(L10nKeys.settingsTitle.tr())),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ListenableBuilder(
            listenable: Listenable.merge([viewModel.saveCommand, _controller]),
            builder: (context, _) {
              final canSave =
                  _controller.text.trim().isNotEmpty &&
                  !viewModel.saveCommand.running;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _controller,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(
                      labelText: L10nKeys.settingsNameLabel.tr(),
                    ),
                    onSubmitted: (value) =>
                        unawaited(viewModel.saveCommand.execute(value)),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: canSave
                        ? () => unawaited(
                            viewModel.saveCommand.execute(_controller.text),
                          )
                        : null,
                    child: Text(L10nKeys.settingsSave.tr()),
                  ),
                  if (viewModel.saveCommand.completed) ...[
                    const SizedBox(height: 16),
                    Text(
                      L10nKeys.settingsSaved.tr(),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  if (viewModel.saveCommand.error) ...[
                    const SizedBox(height: 16),
                    Text(
                      L10nKeys.settingsSaveError.tr(),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
