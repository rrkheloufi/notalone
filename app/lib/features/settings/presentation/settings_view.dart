import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:notalone/core/l10n/l10n_keys.dart';
import 'package:notalone/features/settings/presentation/settings_viewmodel.dart';
import 'package:notalone/features/transcript/domain/transcript_text_scale.dart';

/// Réglages : le prénom et la taille du texte, modifiables à tout moment
/// (doc 01 §3).
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
        child: ListenableBuilder(
          // La taille du texte agrandit l'aperçu, qui peut alors déborder :
          // l'écran défile plutôt que de rogner ce qu'il est censé montrer.
          listenable: Listenable.merge([
            viewModel,
            viewModel.saveCommand,
            _controller,
          ]),
          builder: (context, _) => ListView(
            padding: const EdgeInsets.all(24),
            children: [
              _NameField(
                controller: _controller,
                viewModel: viewModel,
              ),
              const SizedBox(height: 32),
              const Divider(),
              const SizedBox(height: 16),
              _TextSizeSection(viewModel: viewModel),
            ],
          ),
        ),
      ),
    );
  }
}

class _NameField extends StatelessWidget {
  const _NameField({required this.controller, required this.viewModel});

  final TextEditingController controller;
  final SettingsViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final canSave =
        controller.text.trim().isNotEmpty && !viewModel.saveCommand.running;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: controller,
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
              ? () => unawaited(viewModel.saveCommand.execute(controller.text))
              : null,
          child: Text(L10nKeys.settingsSave.tr()),
        ),
        if (viewModel.saveCommand.completed) ...[
          const SizedBox(height: 16),
          Text(L10nKeys.settingsSaved.tr(), textAlign: TextAlign.center),
        ],
        if (viewModel.saveCommand.error) ...[
          const SizedBox(height: 16),
          Text(
            L10nKeys.settingsSaveError.tr(),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}

/// La taille de lecture, avec un **aperçu à la vraie taille**. C'est le seul
/// moyen honnête de choisir : trois libellés « Normale / Grande / Très grande »
/// ne disent rien à qui doit lire à 60 cm, une phrase rendue au corps réel le
/// dit immédiatement.
///
/// Le même réglage est accessible depuis le fil (MVP-12), où le lecteur ajuste
/// en lisant. Les deux écrivent la même préférence.
class _TextSizeSection extends StatelessWidget {
  const _TextSizeSection({required this.viewModel});

  final SettingsViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scale = viewModel.textScale;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          L10nKeys.settingsTextSizeTitle.tr(),
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(
          L10nKeys.settingsTextSizeHint.tr(),
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        SegmentedButton<TranscriptTextScale>(
          segments: [
            for (final value in TranscriptTextScale.values)
              ButtonSegment<TranscriptTextScale>(
                value: value,
                label: Text(_label(value)),
              ),
          ],
          selected: {scale},
          onSelectionChanged: (selection) => unawaited(
            viewModel.textScaleCommand.execute(selection.first),
          ),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            L10nKeys.settingsTextSizePreview.tr(),
            style: TextStyle(
              color: theme.colorScheme.onSurface,
              fontSize: scale.bodySize,
              height: scale.lineHeight,
            ),
          ),
        ),
      ],
    );
  }

  static String _label(TranscriptTextScale scale) => switch (scale) {
    TranscriptTextScale.large => L10nKeys.settingsTextSizeSmall.tr(),
    TranscriptTextScale.extraLarge => L10nKeys.settingsTextSizeMedium.tr(),
    TranscriptTextScale.maximum => L10nKeys.settingsTextSizeLarge.tr(),
  };
}
