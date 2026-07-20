import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:notalone/core/l10n/l10n_keys.dart';
import 'package:notalone/core/theme/speaker_colors.dart';
import 'package:notalone/features/session/domain/discovered_session.dart';
import 'package:notalone/features/session/domain/session_failure.dart';
import 'package:notalone/features/session/presentation/join_viewmodel.dart';

/// Construit la surface de scan. Injectable pour que l'écran soit testable
/// sans la caméra : `MobileScanner` passe par un platform channel absent des
/// widget tests.
typedef QrScannerBuilder =
    Widget Function(BuildContext context, ValueChanged<String> onScanned);

/// Parcours « Rejoindre » : scanner le QR (ou choisir une session trouvée sur
/// le réseau), confirmer son prénom, c'est tout
/// (cf. cowork/01-cadrage-produit.md §3).
class JoinView extends StatefulWidget {
  const JoinView({
    required this.viewModel,
    this.scannerBuilder = _buildMobileScanner,
    super.key,
  });

  final JoinViewModel viewModel;
  final QrScannerBuilder scannerBuilder;

  static Widget _buildMobileScanner(
    BuildContext context,
    ValueChanged<String> onScanned,
  ) => MobileScanner(
    onDetect: (capture) {
      final raw = capture.barcodes.isEmpty
          ? null
          : capture.barcodes.first.rawValue;
      if (raw != null) onScanned(raw);
    },
  );

  @override
  State<JoinView> createState() => _JoinViewState();
}

class _JoinViewState extends State<JoinView> {
  late final TextEditingController _nameController = TextEditingController(
    text: widget.viewModel.name,
  );

  @override
  void initState() {
    super.initState();
    unawaited(widget.viewModel.discoverCommand.execute());
  }

  @override
  void dispose() {
    _nameController.dispose();
    widget.viewModel.dispose();
    super.dispose();
  }

  void _onScanned(String raw) {
    if (widget.viewModel.scanCommand.running) return;
    unawaited(widget.viewModel.scanCommand.execute(raw));
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = widget.viewModel;
    return Scaffold(
      appBar: AppBar(title: Text(L10nKeys.joinTitle.tr())),
      body: ListenableBuilder(
        listenable: Listenable.merge([
          viewModel,
          viewModel.scanCommand,
          viewModel.joinCommand,
        ]),
        builder: (context, _) => switch (viewModel.step) {
          JoinStep.scanning => _Scanning(
            viewModel: viewModel,
            scanner: widget.scannerBuilder(context, _onScanned),
          ),
          JoinStep.confirmingName || JoinStep.connecting => _ConfirmName(
            viewModel: viewModel,
            controller: _nameController,
          ),
          JoinStep.connected => _Connected(viewModel: viewModel),
          JoinStep.reconnecting => _Reconnecting(viewModel: viewModel),
          JoinStep.lost => _Terminal(
            icon: Icons.wifi_off,
            message: viewModel.lostReason ?? L10nKeys.joinConnectionLost.tr(),
            actionLabel: L10nKeys.joinRescan.tr(),
            onAction: () => unawaited(viewModel.backToScanning()),
          ),
          JoinStep.ended => _Terminal(
            icon: Icons.done_all,
            message: L10nKeys.joinSessionEnded.tr(),
            actionLabel: L10nKeys.joinRescan.tr(),
            onAction: () => unawaited(viewModel.backToScanning()),
          ),
        },
      ),
    );
  }
}

class _Scanning extends StatelessWidget {
  const _Scanning({required this.viewModel, required this.scanner});

  final JoinViewModel viewModel;
  final Widget scanner;

  @override
  Widget build(BuildContext context) {
    final failure = viewModel.scanCommand.result?.failureOrNull;
    final message = switch (failure) {
      null => L10nKeys.joinScanHint.tr(),
      ConnectionTimeoutFailure() => L10nKeys.joinTimeoutHint.tr(),
      _ => failure.message,
    };
    return Column(
      children: [
        Expanded(child: scanner),
        Material(
          color: Theme.of(context).colorScheme.surface,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(message, textAlign: TextAlign.center),
                if (viewModel.discoveredSessions.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    L10nKeys.joinDiscoveredTitle.tr(),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  for (final discovered in viewModel.discoveredSessions)
                    _DiscoveredTile(viewModel: viewModel, session: discovered),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _DiscoveredTile extends StatelessWidget {
  const _DiscoveredTile({required this.viewModel, required this.session});

  final JoinViewModel viewModel;
  final DiscoveredSession session;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.wifi_find),
      title: Text(session.sessionName),
      onTap: () => unawaited(viewModel.pickCommand.execute(session)),
    );
  }
}

class _ConfirmName extends StatelessWidget {
  const _ConfirmName({required this.viewModel, required this.controller});

  final JoinViewModel viewModel;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final connecting = viewModel.step == JoinStep.connecting;
    final failure = viewModel.joinCommand.result?.failureOrNull;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            L10nKeys.joinSessionFound.tr(
              namedArgs: {
                'session': viewModel.pendingSession?.sessionName ?? '',
              },
            ),
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          TextField(
            controller: controller,
            enabled: !connecting,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: L10nKeys.joinNameLabel.tr(),
            ),
            onSubmitted: (value) =>
                unawaited(viewModel.joinCommand.execute(value)),
          ),
          if (failure != null) ...[
            const SizedBox(height: 12),
            Text(
              failure.message,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: connecting
                ? null
                : () => unawaited(
                    viewModel.joinCommand.execute(controller.text),
                  ),
            child: Text(
              connecting
                  ? L10nKeys.joinConnecting.tr()
                  : L10nKeys.joinConfirm.tr(),
            ),
          ),
        ],
      ),
    );
  }
}

class _Connected extends StatelessWidget {
  const _Connected({required this.viewModel});

  final JoinViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final session = viewModel.session;
    final color = session == null
        ? Theme.of(context).colorScheme.primary
        : SpeakerColors.at(session.colorIndex);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 40,
              backgroundColor: color,
              child: const Icon(Icons.check, color: Colors.white, size: 40),
            ),
            const SizedBox(height: 24),
            Text(
              L10nKeys.joinConnected.tr(namedArgs: {'name': viewModel.name}),
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              L10nKeys.joinConnectedHint.tr(),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            OutlinedButton(
              onPressed: () => unawaited(viewModel.backToScanning()),
              child: Text(L10nKeys.joinLeave.tr()),
            ),
          ],
        ),
      ),
    );
  }
}

class _Reconnecting extends StatelessWidget {
  const _Reconnecting({required this.viewModel});

  final JoinViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 24),
          Text(
            L10nKeys.joinReconnecting.tr(
              namedArgs: {'attempt': '${viewModel.reconnectAttempt}'},
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _Terminal extends StatelessWidget {
  const _Terminal({
    required this.icon,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 48),
            const SizedBox(height: 24),
            Text(
              message,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}
