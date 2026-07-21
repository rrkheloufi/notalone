import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:notalone/core/l10n/l10n_keys.dart';
import 'package:notalone/core/theme/speaker_colors.dart';
import 'package:notalone/features/session/domain/participant.dart';
import 'package:notalone/features/session/presentation/host_lobby_viewmodel.dart';
import 'package:notalone/features/transcript/presentation/transcript_view.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';

/// Salon de l'hôte : « Nouvelle conversation » → un QR s'affiche → les autres
/// le scannent (cf. cowork/01-cadrage-produit.md §3).
class HostLobbyView extends StatefulWidget {
  const HostLobbyView({required this.viewModel, super.key});

  final HostLobbyViewModel viewModel;

  @override
  State<HostLobbyView> createState() => _HostLobbyViewState();
}

class _HostLobbyViewState extends State<HostLobbyView> {
  @override
  void initState() {
    super.initState();
    unawaited(widget.viewModel.startCommand.execute());
  }

  @override
  void dispose() {
    widget.viewModel.dispose();
    super.dispose();
  }

  Future<void> _endSession() async {
    await widget.viewModel.endSessionCommand.execute();
    if (mounted) Navigator.of(context).pop();
  }

  /// Le fil est **empilé** sur le salon, pas substitué : le QR reste à un
  /// retour d'ici, et le ViewModel du fil survit à la fermeture de l'écran —
  /// c'est le salon qui le possède.
  void _openTranscript() {
    final transcript = widget.viewModel.transcript;
    if (transcript == null) return;
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => TranscriptView(
            viewModel: transcript,
            sessionName: widget.viewModel.sessionName,
            qrData: widget.viewModel.qrData,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = widget.viewModel;
    return Scaffold(
      appBar: AppBar(title: Text(L10nKeys.hostLobbyTitle.tr())),
      body: ListenableBuilder(
        listenable: Listenable.merge([
          viewModel,
          viewModel.startCommand,
          viewModel.endSessionCommand,
        ]),
        builder: (context, _) {
          final failure = viewModel.startCommand.result?.failureOrNull;
          if (failure != null) {
            return _StartFailure(
              message: failure.message,
              onRetry: () => unawaited(viewModel.startCommand.execute()),
            );
          }
          if (!viewModel.isRunning) {
            return const Center(child: CircularProgressIndicator());
          }
          return _Lobby(
            viewModel: viewModel,
            onEndSession: _endSession,
            onOpenTranscript: _openTranscript,
          );
        },
      ),
    );
  }
}

class _Lobby extends StatelessWidget {
  const _Lobby({
    required this.viewModel,
    required this.onEndSession,
    required this.onOpenTranscript,
  });

  final HostLobbyViewModel viewModel;
  final Future<void> Function() onEndSession;
  final VoidCallback onOpenTranscript;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              L10nKeys.hostLobbyScanMe.tr(),
              style: textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Center(
              child: Container(
                padding: const EdgeInsets.all(12),
                // Fond blanc imposé : un QR sur fond sombre ne se scanne pas.
                color: Colors.white,
                child: SizedBox(
                  width: 240,
                  height: 240,
                  child: PrettyQrView.data(data: viewModel.qrData!),
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (viewModel.isDiscoverable)
              Text(
                L10nKeys.hostLobbyDiscoverable.tr(),
                style: textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            if (viewModel.lastRejection != null) ...[
              const SizedBox(height: 8),
              _RejectionBanner(
                message: viewModel.lastRejection!,
                onDismiss: viewModel.clearRejection,
              ),
            ],
            const SizedBox(height: 16),
            Text(
              L10nKeys.hostLobbyParticipants.tr(
                namedArgs: {'count': '${viewModel.participants.length}'},
              ),
              style: textTheme.titleMedium,
            ),
            Expanded(
              child: ListView.builder(
                itemCount: viewModel.participants.length,
                itemBuilder: (context, index) => _ParticipantTile(
                  participant: viewModel.participants[index],
                ),
              ),
            ),
            // Le fil est l'écran où l'hôte passe le repas : il est l'action
            // principale, la fin de session reste discrète juste dessous.
            if (viewModel.transcript != null)
              FilledButton.icon(
                onPressed: onOpenTranscript,
                icon: const Icon(Icons.forum),
                label: Text(L10nKeys.hostLobbyStart.tr()),
              ),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: viewModel.endSessionCommand.running
                  ? null
                  : () => unawaited(onEndSession()),
              icon: const Icon(Icons.stop_circle_outlined),
              label: Text(L10nKeys.hostLobbyEndSession.tr()),
            ),
          ],
        ),
      ),
    );
  }
}

class _ParticipantTile extends StatelessWidget {
  const _ParticipantTile({required this.participant});

  final Participant participant;

  @override
  Widget build(BuildContext context) {
    final color = SpeakerColors.at(participant.colorIndex);
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color,
        child: Text(
          participant.name.characters.first.toUpperCase(),
          style: const TextStyle(color: Colors.white),
        ),
      ),
      title: Text(participant.name),
      subtitle: Text(
        participant.isHost
            ? L10nKeys.hostLobbyYou.tr()
            : participant.isConnected
            ? L10nKeys.hostLobbyConnected.tr()
            : L10nKeys.hostLobbyDisconnected.tr(),
      ),
      trailing: participant.isConnected
          ? null
          : const Icon(Icons.signal_wifi_off),
    );
  }
}

class _RejectionBanner extends StatelessWidget {
  const _RejectionBanner({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: scheme.onErrorContainer),
            ),
          ),
          IconButton(onPressed: onDismiss, icon: const Icon(Icons.close)),
        ],
      ),
    );
  }
}

class _StartFailure extends StatelessWidget {
  const _StartFailure({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onRetry,
              child: Text(L10nKeys.commonRetry.tr()),
            ),
          ],
        ),
      ),
    );
  }
}
