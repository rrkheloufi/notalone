import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:notalone/core/l10n/l10n_keys.dart';
import 'package:notalone/core/theme/speaker_colors.dart';
import 'package:notalone/features/transcript/domain/transcript_text_scale.dart';
import 'package:notalone/features/transcript/presentation/transcript_message.dart';
import 'package:notalone/features/transcript/presentation/transcript_viewmodel.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';

/// L'écran que regarde la personne malentendante : la conversation s'écrit ici
/// (cf. cowork/01-cadrage-produit.md §3).
///
/// Ne dispose **pas** son ViewModel : celui-ci est né avec la session et lui
/// survit — le lecteur peut revenir au QR puis rouvrir le fil sans que rien ne
/// se perde. C'est le salon qui le ferme (cf. `HostLobbyViewModel`).
class TranscriptView extends StatefulWidget {
  const TranscriptView({
    required this.viewModel,
    this.sessionName,
    this.qrData,
    super.key,
  });

  final TranscriptViewModel viewModel;

  /// Titre affiché ; le libellé générique sert de secours.
  final String? sessionName;

  /// Payload du QR, pour faire entrer un retardataire sans quitter le fil.
  /// Nul quand la session n'expose pas de QR (tests, session terminée).
  final String? qrData;

  @override
  State<TranscriptView> createState() => _TranscriptViewState();
}

class _TranscriptViewState extends State<TranscriptView> {
  /// `reverse: true` : l'offset 0 est le bas de l'écran, donc la phrase la plus
  /// récente. Le fil se comporte alors comme une messagerie — il n'a rien à
  /// faire défiler pour rester au plus récent, ce qui est exactement la
  /// garantie « jamais de scroll forcé ».
  final ScrollController _controller = ScrollController();

  /// Sous ce nombre de pixels on considère le lecteur « au plus récent » : un
  /// pouce qui frôle la liste ne doit pas suspendre le suivi.
  static const double _followThresholdPx = 48;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
    unawaited(widget.viewModel.loadCommand.execute());
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_controller.hasClients) return;
    widget.viewModel.setFollowing(
      following: _controller.position.pixels <= _followThresholdPx,
    );
  }

  void _backToLatest() {
    widget.viewModel.setFollowing(following: true);
    if (_controller.hasClients) {
      unawaited(
        _controller.animateTo(
          0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        ),
      );
    }
  }

  void _showQr() {
    final data = widget.qrData;
    if (data == null) return;
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        builder: (context) => _QrSheet(data: data),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = widget.viewModel;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.sessionName ?? L10nKeys.transcriptTitle.tr()),
        actions: [
          if (widget.qrData != null)
            IconButton(
              onPressed: _showQr,
              tooltip: L10nKeys.transcriptShowQr.tr(),
              icon: const Icon(Icons.qr_code_2),
            ),
          ListenableBuilder(
            listenable: viewModel,
            builder: (context, _) => Row(
              children: [
                IconButton(
                  onPressed: viewModel.textScale.hasSmaller
                      ? () => unawaited(viewModel.reduceTextCommand.execute())
                      : null,
                  tooltip: L10nKeys.transcriptTextSmaller.tr(),
                  icon: const Icon(Icons.text_decrease),
                ),
                IconButton(
                  onPressed: viewModel.textScale.hasLarger
                      ? () => unawaited(viewModel.enlargeTextCommand.execute())
                      : null,
                  tooltip: L10nKeys.transcriptTextLarger.tr(),
                  icon: const Icon(Icons.text_increase),
                ),
              ],
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: viewModel,
          builder: (context, _) {
            final messages = viewModel.visibleMessages;
            return Column(
              children: [
                if (viewModel.isFiltered)
                  _FilterBanner(
                    // Le prénom peut manquer si l'annuaire ne connaît pas
                    // encore ce convive : le filtre reste utilisable.
                    name:
                        viewModel.filteredSpeaker?.name ??
                        L10nKeys.transcriptUnknownSpeaker.tr(),
                    onClear: viewModel.clearSpeakerFilter,
                  ),
                Expanded(
                  child: Stack(
                    children: [
                      if (messages.isEmpty)
                        _EmptyThread(
                          filteredName: viewModel.isFiltered
                              ? viewModel.filteredSpeaker?.name ??
                                    L10nKeys.transcriptUnknownSpeaker.tr()
                              : null,
                        )
                      else
                        ListView.builder(
                          controller: _controller,
                          reverse: true,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          itemCount: messages.length,
                          itemBuilder: (context, index) => _MessageBubble(
                            // Le plus récent en bas : `reverse` rend l'index 0
                            // au ras du bord inférieur.
                            message: messages[messages.length - 1 - index],
                            scale: viewModel.textScale,
                            onSpeakerTap: viewModel.toggleSpeakerFilter,
                          ),
                        ),
                      if (viewModel.hasUnread)
                        _NewMessagesBadge(
                          count: viewModel.unreadCount,
                          onTap: _backToLatest,
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Une prise de parole. Le prénom est un bouton : l'appuyer isole ce locuteur,
/// l'appuyer de nouveau rend tout le monde (critère « 1 geste »).
class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.scale,
    required this.onSpeakerTap,
  });

  final TranscriptMessage message;
  final TranscriptTextScale scale;
  final void Function(String participantId) onSpeakerTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final speaker = message.speaker;
    final color = SpeakerColors.onSurface(speaker?.colorIndex ?? 0, brightness);
    final name = speaker?.name ?? L10nKeys.transcriptUnknownSpeaker.tr();
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => onSpeakerTap(message.participantId),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      name,
                      style: TextStyle(
                        color: color,
                        fontSize: scale.speakerSize,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (message.isLate) ...[
                    const SizedBox(width: 8),
                    // Discret et textuel : le lecteur doit pouvoir comprendre
                    // pourquoi cette phrase arrive après coup, sans que cela
                    // vole la vedette à ce qui est dit (décision MVP-09).
                    Icon(
                      Icons.schedule,
                      size: scale.speakerSize,
                      color: theme.colorScheme.outline,
                      semanticLabel: L10nKeys.transcriptLate.tr(),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Text(
            message.text,
            style: TextStyle(
              // `onSurface` et non la couleur du locuteur : la phrase se lit
              // au contraste maximal, la teinte ne sert qu'à l'attribution.
              color: theme.colorScheme.onSurface,
              fontSize: scale.bodySize,
              height: scale.lineHeight,
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterBanner extends StatelessWidget {
  const _FilterBanner({required this.name, required this.onClear});

  final String name;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                L10nKeys.transcriptFilterActive.tr(namedArgs: {'name': name}),
                style: TextStyle(color: scheme.onSecondaryContainer),
              ),
            ),
            TextButton.icon(
              onPressed: onClear,
              icon: const Icon(Icons.close),
              label: Text(L10nKeys.transcriptFilterClear.tr()),
            ),
          ],
        ),
      ),
    );
  }
}

class _NewMessagesBadge extends StatelessWidget {
  const _NewMessagesBadge({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 16,
      child: Center(
        child: FilledButton.icon(
          onPressed: onTap,
          icon: const Icon(Icons.arrow_downward),
          label: Text(L10nKeys.transcriptNewMessages.plural(count)),
        ),
      ),
    );
  }
}

class _EmptyThread extends StatelessWidget {
  const _EmptyThread({required this.filteredName});

  /// Non nul quand c'est le filtre, et non le silence, qui vide l'écran : les
  /// deux situations ne se disent pas de la même façon.
  final String? filteredName;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final name = filteredName;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.forum_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              name == null
                  ? L10nKeys.transcriptEmpty.tr()
                  : L10nKeys.transcriptFilterEmpty.tr(
                      namedArgs: {'name': name},
                    ),
              style: textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            if (name == null) ...[
              const SizedBox(height: 8),
              Text(
                L10nKeys.transcriptEmptyHint.tr(),
                style: textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _QrSheet extends StatelessWidget {
  const _QrSheet({required this.data});

  final String data;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              L10nKeys.transcriptQrTitle.tr(),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              // Fond blanc imposé : un QR sur fond sombre ne se scanne pas.
              color: Colors.white,
              child: SizedBox(
                width: 220,
                height: 220,
                child: PrettyQrView.data(data: data),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
