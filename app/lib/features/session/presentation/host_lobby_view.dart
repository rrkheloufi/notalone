import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:notalone/core/l10n/l10n_keys.dart';
import 'package:notalone/features/capture/domain/capture_status.dart';
import 'package:notalone/features/session/presentation/host_lobby_viewmodel.dart';
import 'package:notalone/features/session/presentation/supervision_banner.dart';
import 'package:notalone/features/session/presentation/supervision_panel.dart';
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

  /// Fin de session en deux temps (décision Rayan, MVP-13) : on **demande
  /// confirmation** — un appui malheureux au milieu d'un repas obligerait tout
  /// le monde à rescanner — puis on montre un écran qui dit noir sur blanc que
  /// le texte a été effacé. C'est la promesse d'éphémérité du doc 03 §RGPD
  /// rendue visible, et non seulement tenue en silence.
  Future<void> _endSession() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => const _EndSessionDialog(),
    );
    if (confirmed != true || !mounted) return;
    await widget.viewModel.endSessionCommand.execute();
  }

  /// Le fil est **empilé** sur le salon, pas substitué : le QR reste à un
  /// retour d'ici, et le ViewModel du fil survit à la fermeture de l'écran —
  /// c'est le salon qui le possède.
  void _openTranscript() {
    final viewModel = widget.viewModel;
    final transcript = viewModel.transcript;
    if (transcript == null) return;
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (routeContext) => TranscriptView(
            viewModel: transcript,
            sessionName: viewModel.sessionName,
            qrData: viewModel.qrData,
            // Construit ici, par `session/` : le fil se contente de le poser
            // en haut de l'écran sans rien savoir de la supervision.
            supervisionBanner: ListenableBuilder(
              listenable: viewModel,
              builder: (context, _) => SupervisionBanner(
                alerts: viewModel.alerts,
                onOpenPanel: () => Navigator.of(routeContext).pop(),
              ),
            ),
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
          // Testé avant tout le reste : une session terminée n'a plus ni QR
          // ni participants à afficher, et surtout plus rien du transcript.
          if (viewModel.isEnded) {
            return _SessionEnded(
              onBackHome: () => Navigator.of(context).pop(),
            );
          }
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
              child: SupervisionPanel(
                participants: viewModel.participants,
                // L'hôte capte sa propre voix (doc 02 §1) : sa ligne lui donne
                // de quoi se couper le micro sans quitter le salon.
                onToggleHostMute: viewModel.hostCapture == null
                    ? null
                    : () => unawaited(
                        viewModel.hostCapture!.toggleMuteCommand.execute(),
                      ),
                isHostMuted:
                    viewModel.hostCapture?.status == CaptureStatus.muted,
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

/// Le garde-fou avant d'effacer : l'action est irréversible et coûte à tout le
/// monde (chacun doit rescanner), la conséquence est donc énoncée avant, pas
/// après.
class _EndSessionDialog extends StatelessWidget {
  const _EndSessionDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(L10nKeys.hostLobbyEndConfirmTitle.tr()),
      content: Text(L10nKeys.hostLobbyEndConfirmMessage.tr()),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(L10nKeys.hostLobbyEndConfirmCancel.tr()),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(L10nKeys.hostLobbyEndConfirmAccept.tr()),
        ),
      ],
    );
  }
}

/// L'écran terminal. Il ne montre plus rien de la conversation — c'est tout son
/// propos : le lecteur doit **voir** qu'il ne reste rien, pas seulement qu'on
/// le lui promette (critère « aucune trace du transcript », MVP-13).
class _SessionEnded extends StatelessWidget {
  const _SessionEnded({required this.onBackHome});

  final VoidCallback onBackHome;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 64,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              L10nKeys.hostLobbyEndedTitle.tr(),
              style: theme.textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              L10nKeys.hostLobbyEndedMessage.tr(),
              style: theme.textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: onBackHome,
              child: Text(L10nKeys.hostLobbyEndedBackHome.tr()),
            ),
          ],
        ),
      ),
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
