import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:notalone/core/l10n/l10n_keys.dart';
import 'package:notalone/features/session/presentation/lan_host_debug_viewmodel.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';

/// Écran hôte jetable du spike MVP-03 : serveur + QR + journal.
class LanHostDebugView extends StatefulWidget {
  const LanHostDebugView({required this.viewModel, super.key});

  final LanHostDebugViewModel viewModel;

  @override
  State<LanHostDebugView> createState() => _LanHostDebugViewState();
}

class _LanHostDebugViewState extends State<LanHostDebugView> {
  final TextEditingController _messageController = TextEditingController();

  @override
  void dispose() {
    _messageController.dispose();
    widget.viewModel.dispose();
    super.dispose();
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
      appBar: AppBar(title: Text(L10nKeys.lanDebugHostTitle.tr())),
      body: ListenableBuilder(
        listenable: Listenable.merge([
          viewModel,
          viewModel.startCommand,
          viewModel.stopCommand,
        ]),
        builder: (context, _) {
          final failure = viewModel.startCommand.result?.failureOrNull;
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (failure != null) _Banner(message: failure.message),
                if (!viewModel.isRunning)
                  FilledButton.icon(
                    onPressed: viewModel.startCommand.running
                        ? null
                        : () => unawaited(viewModel.startCommand.execute()),
                    icon: const Icon(Icons.wifi_tethering),
                    label: Text(L10nKeys.lanDebugStartServer.tr()),
                  )
                else ...[
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      color: Colors.white,
                      child: SizedBox(
                        width: 220,
                        height: 220,
                        child: PrettyQrView.data(data: viewModel.qrData!),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: Text(
                      L10nKeys.lanDebugServerAddress.tr(
                        namedArgs: {
                          'host': '${viewModel.host}',
                          'port': '${viewModel.port}',
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: viewModel.stopCommand.running
                        ? null
                        : () => unawaited(viewModel.stopCommand.execute()),
                    icon: const Icon(Icons.stop),
                    label: Text(L10nKeys.lanDebugStopServer.tr()),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _messageController,
                          decoration: InputDecoration(
                            hintText: L10nKeys.lanDebugSendHint.tr(),
                          ),
                          onSubmitted: (_) => _send(),
                        ),
                      ),
                      IconButton(
                        onPressed: _send,
                        icon: const Icon(Icons.send),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(child: _HostLog(entries: viewModel.log)),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _HostLog extends StatelessWidget {
  const _HostLog({required this.entries});

  final List<HostLogEntry> entries;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return Center(child: Text(L10nKeys.lanDebugNoEvents.tr()));
    }
    return ListView.builder(
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[entries.length - 1 - index];
        final label = switch (entry) {
          GuestJoinedEntry(:final clientId) => L10nKeys.lanDebugGuestJoined.tr(
            namedArgs: {'id': '$clientId'},
          ),
          GuestLeftEntry(:final clientId) => L10nKeys.lanDebugGuestLeft.tr(
            namedArgs: {'id': '$clientId'},
          ),
          GuestMessageEntry(:final clientId, :final text) =>
            L10nKeys.lanDebugGuestMessage.tr(
              namedArgs: {'id': '$clientId', 'text': text},
            ),
          HostMessageEntry(:final text) => L10nKeys.lanDebugHostMessage.tr(
            namedArgs: {'text': text},
          ),
        };
        return ListTile(dense: true, title: Text(label));
      },
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(message, style: TextStyle(color: scheme.onErrorContainer)),
    );
  }
}
