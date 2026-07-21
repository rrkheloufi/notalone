import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:notalone/core/l10n/l10n_keys.dart';
import 'package:notalone/core/theme/speaker_colors.dart';
import 'package:notalone/features/session/domain/participant_supervision.dart';
import 'package:notalone/features/session/domain/protocol/session_message.dart';

/// Icône et couleur d'une alerte de supervision. Regroupées ici parce que le
/// panneau du salon et le bandeau du fil doivent dire la même chose de la même
/// façon : deux vocabulaires visuels pour un seul état dérouteraient l'hôte.
///
/// La couleur ne porte jamais seule l'information — chaque ligne du panneau
/// est doublée de son libellé en toutes lettres, comme les bulles du fil
/// (décision MVP-12).
({IconData icon, Color color}) supervisionAppearance(
  SupervisionAlert alert,
  ColorScheme scheme,
) => switch (alert) {
  SupervisionAlert.disconnected => (
    icon: Icons.signal_wifi_off,
    color: scheme.error,
  ),
  SupervisionAlert.interrupted => (
    icon: Icons.phone_in_talk,
    color: scheme.error,
  ),
  SupervisionAlert.muted => (icon: Icons.mic_off, color: scheme.error),
  // Avertissement et non panne : le micro capte encore, la couleur reste
  // sourde pour ne pas hurler ce qui n'est pas urgent (doc 03 R1).
  SupervisionAlert.lowBattery => (
    icon: Icons.battery_alert,
    color: scheme.tertiary,
  ),
  SupervisionAlert.none => (icon: Icons.mic, color: scheme.outline),
};

/// Le panneau de supervision de l'hôte : qui est là, et est-ce que son micro
/// marche (cf. cowork/01-cadrage-produit.md §7.5).
///
/// Il vit au salon, l'écran du QR. Le fil, où l'hôte passe le repas, n'en
/// montre qu'un bandeau — c'est `SupervisionBanner`.
class SupervisionPanel extends StatelessWidget {
  const SupervisionPanel({
    required this.participants,
    this.onToggleHostMute,
    this.isHostMuted = false,
    super.key,
  });

  final List<ParticipantSupervision> participants;

  /// Non nul quand la capture de l'hôte tourne : sa propre ligne gagne alors
  /// de quoi couper son micro sans quitter le salon.
  final VoidCallback? onToggleHostMute;

  final bool isHostMuted;

  @override
  Widget build(BuildContext context) => ListView.builder(
    itemCount: participants.length,
    itemBuilder: (context, index) {
      final supervised = participants[index];
      return SupervisionTile(
        supervised: supervised,
        onToggleMute: supervised.isHost ? onToggleHostMute : null,
        isMuted: isHostMuted,
      );
    },
  );
}

/// Une ligne du panneau : prénom, couleur du locuteur, état du micro.
class SupervisionTile extends StatelessWidget {
  const SupervisionTile({
    required this.supervised,
    this.onToggleMute,
    this.isMuted = false,
    super.key,
  });

  final ParticipantSupervision supervised;
  final VoidCallback? onToggleMute;
  final bool isMuted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final appearance = supervisionAppearance(supervised.alert, scheme);
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: SpeakerColors.at(supervised.participant.colorIndex),
        child: Text(
          supervised.name.characters.first.toUpperCase(),
          style: const TextStyle(color: Colors.white),
        ),
      ),
      title: Text(
        supervised.isHost
            ? '${supervised.name} (${L10nKeys.hostLobbyYou.tr()})'
            : supervised.name,
      ),
      subtitle: Text(
        _subtitle(supervised),
        style: supervised.hasAlert
            ? TextStyle(color: appearance.color)
            : null,
      ),
      trailing: onToggleMute == null
          ? (supervised.hasAlert
                ? Icon(appearance.icon, color: appearance.color)
                : null)
          : IconButton(
              onPressed: onToggleMute,
              icon: Icon(isMuted ? Icons.mic_off : Icons.mic),
              tooltip: isMuted
                  ? L10nKeys.hostLobbyUnmuteSelf.tr()
                  : L10nKeys.hostLobbyMuteSelf.tr(),
            ),
    );
  }

  /// Une ligne qui dit l'état du micro **et** la batterie quand elle est
  /// connue : ce sont les deux seules choses que l'hôte peut traiter, l'une en
  /// interpellant le convive, l'autre en lui tendant un chargeur.
  static String _subtitle(ParticipantSupervision supervised) {
    if (supervised.alert == SupervisionAlert.disconnected) {
      return L10nKeys.hostLobbyDisconnected.tr();
    }
    final mic = switch (supervised.micState) {
      MicStatusState.active => L10nKeys.hostLobbyMicActive.tr(),
      MicStatusState.muted => L10nKeys.hostLobbyMicMuted.tr(),
      MicStatusState.interrupted => L10nKeys.hostLobbyMicInterrupted.tr(),
      // Pas encore de `mic_status` : on ne prétend pas savoir. Un « micro
      // actif » optimiste ferait croire à l'hôte que tout va bien.
      null => L10nKeys.hostLobbyMicUnknown.tr(),
    };
    final battery = supervised.batteryPct;
    if (battery == null) return mic;
    final args = {'pct': '$battery'};
    final level = supervised.alert == SupervisionAlert.lowBattery
        ? L10nKeys.hostLobbyBatteryLow.tr(namedArgs: args)
        : L10nKeys.hostLobbyBattery.tr(namedArgs: args);
    return '$mic · $level';
  }
}
