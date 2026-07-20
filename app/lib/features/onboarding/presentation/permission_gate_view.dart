import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:notalone/core/l10n/l10n_keys.dart';
import 'package:notalone/features/onboarding/domain/permission_service.dart';
import 'package:notalone/features/onboarding/presentation/permission_gate_viewmodel.dart';

/// Écran d'explication d'une permission, ouvert juste avant qu'elle serve
/// (cf. cowork/01-cadrage-produit.md §3 : jamais de demande à froid).
///
/// Se referme sur un [PermissionOutcome] : accordée, passée outre, ou annulée
/// par un retour arrière.
class PermissionGateView extends StatefulWidget {
  const PermissionGateView({required this.viewModel, super.key});

  final PermissionGateViewModel viewModel;

  @override
  State<PermissionGateView> createState() => _PermissionGateViewState();
}

class _PermissionGateViewState extends State<PermissionGateView> {
  @override
  void dispose() {
    widget.viewModel.dispose();
    super.dispose();
  }

  Future<void> _request() async {
    await widget.viewModel.requestCommand.execute();
    if (!mounted || !widget.viewModel.isGranted) return;
    Navigator.of(context).pop(PermissionOutcome.granted);
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = widget.viewModel;
    final copy = _PermissionCopy.of(viewModel.permission);
    return Scaffold(
      appBar: AppBar(title: Text(copy.title.tr())),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ListenableBuilder(
            listenable: Listenable.merge([
              viewModel,
              viewModel.requestCommand,
              viewModel.openSettingsCommand,
            ]),
            builder: (context, _) => Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(copy.icon, size: 64),
                const SizedBox(height: 24),
                Text(
                  copy.message.tr(),
                  style: Theme.of(context).textTheme.bodyLarge,
                  textAlign: TextAlign.center,
                ),
                if (viewModel.isRefused) ...[
                  const SizedBox(height: 16),
                  Text(
                    copy.refused.tr(),
                    style: Theme.of(context).textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 32),
                if (viewModel.canRequestAgain)
                  FilledButton(
                    onPressed: viewModel.requestCommand.running
                        ? null
                        : () => unawaited(_request()),
                    child: Text(
                      viewModel.isRefused
                          ? L10nKeys.commonRetry.tr()
                          : L10nKeys.permissionAllow.tr(),
                    ),
                  ),
                // Le lien réglages n'apparaît qu'après un refus : iOS ne dit
                // pas toujours qu'il ne redemandera plus, on le propose donc
                // dès le premier refus plutôt qu'au seul refus définitif.
                if (viewModel.isRefused) ...[
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () =>
                        unawaited(viewModel.openSettingsCommand.execute()),
                    child: Text(L10nKeys.permissionOpenSettings.tr()),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () =>
                        Navigator.of(context).pop(PermissionOutcome.skipped),
                    child: Text(copy.skip.tr()),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Textes et icône propres à chaque permission : le tri se fait ici plutôt
/// qu'en paramètres, il n'y en a que deux au MVP.
class _PermissionCopy {
  const _PermissionCopy({
    required this.icon,
    required this.title,
    required this.message,
    required this.refused,
    required this.skip,
  });

  factory _PermissionCopy.of(AppPermission permission) => switch (permission) {
    AppPermission.microphone => const _PermissionCopy(
      icon: Icons.mic,
      title: L10nKeys.permissionMicrophoneTitle,
      message: L10nKeys.permissionMicrophoneMessage,
      refused: L10nKeys.permissionMicrophoneRefused,
      skip: L10nKeys.permissionMicrophoneSkip,
    ),
    AppPermission.camera => const _PermissionCopy(
      icon: Icons.photo_camera,
      title: L10nKeys.permissionCameraTitle,
      message: L10nKeys.permissionCameraMessage,
      refused: L10nKeys.permissionCameraRefused,
      skip: L10nKeys.permissionCameraSkip,
    ),
  };

  final IconData icon;
  final String title;
  final String message;
  final String refused;
  final String skip;
}
