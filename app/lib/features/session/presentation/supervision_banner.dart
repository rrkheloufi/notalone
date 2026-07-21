import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:notalone/core/l10n/l10n_keys.dart';
import 'package:notalone/features/session/domain/participant_supervision.dart';
import 'package:notalone/features/session/presentation/supervision_panel.dart';

/// L'alerte de supervision telle qu'elle apparaît **sur le fil**, l'écran où
/// l'hôte passe le repas (décision Rayan, MVP-13).
///
/// Le panneau complet reste au salon : ici, une seule ligne, la plus grave, et
/// un renvoi vers le panneau. C'est le sens de « non intrusive » — l'alerte ne
/// doit pas disputer la place au texte de la conversation, qui est la raison
/// d'être de l'écran. Mais elle doit exister ici : une alerte affichée
/// uniquement sur un écran que personne ne regarde ne tient pas le critère
/// « coupure du micro visible chez l'hôte en moins de 10 s ».
///
/// Ce widget appartient à `session/` et est **injecté** dans `TranscriptView` :
/// c'est ce qui laisse `transcript/` ignorer `session/` (CLAUDE.md règle 3).
class SupervisionBanner extends StatelessWidget {
  const SupervisionBanner({
    required this.alerts,
    required this.onOpenPanel,
    super.key,
  });

  final List<ParticipantSupervision> alerts;

  /// Ramène au salon, où le panneau détaille chaque convive.
  final VoidCallback onOpenPanel;

  @override
  Widget build(BuildContext context) {
    if (alerts.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    // Les alertes sont déjà triées par gravité dans l'énumération : la plus
    // grave d'abord, c'est celle que l'hôte doit traiter en premier.
    final worst = alerts.reduce(
      (a, b) => b.alert.index > a.alert.index ? b : a,
    );
    final appearance = supervisionAppearance(worst.alert, scheme);
    final others = alerts.length - 1;
    return Material(
      color: scheme.surfaceContainerHighest,
      child: InkWell(
        onTap: onOpenPanel,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(appearance.icon, color: appearance.color, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  others == 0
                      ? _message(worst)
                      : '${_message(worst)} '
                            '${L10nKeys.transcriptAlertMore.plural(others)}',
                  style: TextStyle(color: scheme.onSurface),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                L10nKeys.transcriptAlertOpenPanel.tr(),
                style: TextStyle(
                  color: scheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Une phrase, pas un code d'état : « Le micro de Paul est coupé » est
  /// exactement la formulation que l'objectif de MVP-13 demande.
  static String _message(ParticipantSupervision supervised) {
    final args = {'name': supervised.name};
    return switch (supervised.alert) {
      SupervisionAlert.disconnected => L10nKeys.transcriptAlertDisconnected.tr(
        namedArgs: args,
      ),
      SupervisionAlert.interrupted => L10nKeys.transcriptAlertInterrupted.tr(
        namedArgs: args,
      ),
      SupervisionAlert.muted => L10nKeys.transcriptAlertMuted.tr(
        namedArgs: args,
      ),
      SupervisionAlert.lowBattery => L10nKeys.transcriptAlertLowBattery.tr(
        namedArgs: args,
      ),
      // Inatteignable : le bandeau ne reçoit que des convives en alerte.
      SupervisionAlert.none => '',
    };
  }
}
