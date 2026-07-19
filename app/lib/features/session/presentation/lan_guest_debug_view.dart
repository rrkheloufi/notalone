import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:notalone/core/l10n/l10n_keys.dart';
import 'package:notalone/features/session/domain/session_failure.dart';
import 'package:notalone/features/session/presentation/lan_guest_debug_viewmodel.dart';

/// Écran invité jetable du spike MVP-03 : scan du QR, connexion, RTT,
/// messages de test.
class LanGuestDebugView extends StatefulWidget {
  const LanGuestDebugView({required this.viewModel, super.key});

  final LanGuestDebugViewModel viewModel;

  @override
  State<LanGuestDebugView> createState() => _LanGuestDebugViewState();
}

class _LanGuestDebugViewState extends State<LanGuestDebugView> {
  final TextEditingController _messageController = TextEditingController();

  @override
  void dispose() {
    _messageController.dispose();
    widget.viewModel.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (widget.viewModel.scanCommand.running) return;
    final raw = capture.barcodes.isEmpty
        ? null
        : capture.barcodes.first.rawValue;
    if (raw != null) unawaited(widget.viewModel.scanCommand.execute(raw));
  }

  void _send() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    unawaited(widget.viewModel.sendCommand.execute(text));
    _messageController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = widget.viewModel;
    return Scaffold(
      appBar: AppBar(title: Text(L10nKeys.lanDebugGuestTitle.tr())),
      body: ListenableBuilder(
        listenable: Listenable.merge([
          viewModel,
          viewModel.scanCommand,
          viewModel.measureRttCommand,
        ]),
        builder: (context, _) => switch (viewModel.state) {
          GuestConnectionState.scanning => _Scanner(
            viewModel: viewModel,
            onDetect: _onDetect,
          ),
          GuestConnectionState.connected => _Connected(
            viewModel: viewModel,
            messageController: _messageController,
            onSend: _send,
          ),
          GuestConnectionState.disconnected => _Disconnected(
            viewModel: viewModel,
          ),
        },
      ),
    );
  }
}

class _Scanner extends StatelessWidget {
  const _Scanner({required this.viewModel, required this.onDetect});

  final LanGuestDebugViewModel viewModel;
  final void Function(BarcodeCapture) onDetect;

  @override
  Widget build(BuildContext context) {
    final failure = viewModel.scanCommand.result?.failureOrNull;
    final message = switch (failure) {
      null => L10nKeys.lanDebugScanHint.tr(),
      ConnectionTimeoutFailure() => L10nKeys.lanDebugTimeoutHint.tr(),
      _ => failure.message,
    };
    return Stack(
      children: [
        MobileScanner(onDetect: onDetect),
        Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
            child: Text(
              viewModel.scanCommand.running
                  ? L10nKeys.lanDebugConnecting.tr()
                  : message,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    );
  }
}

class _Connected extends StatelessWidget {
  const _Connected({
    required this.viewModel,
    required this.messageController,
    required this.onSend,
  });

  final LanGuestDebugViewModel viewModel;
  final TextEditingController messageController;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final medianRtt = viewModel.medianRtt;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle, color: scheme.primary),
              const SizedBox(width: 8),
              Text(L10nKeys.lanDebugConnected.tr()),
              const Spacer(),
              if (viewModel.measureRttCommand.running)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else if (medianRtt != null)
                Text(
                  L10nKeys.lanDebugMedianRtt.tr(
                    namedArgs: {'ms': '${medianRtt.inMilliseconds}'},
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: viewModel.measureRttCommand.running
                ? null
                : () => unawaited(viewModel.measureRttCommand.execute()),
            child: Text(L10nKeys.lanDebugPingAgain.tr()),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: messageController,
                  decoration: InputDecoration(
                    hintText: L10nKeys.lanDebugSendHint.tr(),
                  ),
                  onSubmitted: (_) => onSend(),
                ),
              ),
              IconButton(onPressed: onSend, icon: const Icon(Icons.send)),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              itemCount: viewModel.messages.length,
              itemBuilder: (context, index) {
                final entry =
                    viewModel.messages[viewModel.messages.length - 1 - index];
                final label = entry.own
                    ? L10nKeys.lanDebugOwnMessage.tr(
                        namedArgs: {'text': entry.text},
                      )
                    : L10nKeys.lanDebugRemoteMessage.tr(
                        namedArgs: {'text': entry.text},
                      );
                return ListTile(dense: true, title: Text(label));
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Disconnected extends StatelessWidget {
  const _Disconnected({required this.viewModel});

  final LanGuestDebugViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(L10nKeys.lanDebugDisconnected.tr()),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: viewModel.resetToScan,
            child: Text(L10nKeys.lanDebugRescan.tr()),
          ),
        ],
      ),
    );
  }
}
