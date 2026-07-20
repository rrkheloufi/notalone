import 'package:notalone/core/result/result.dart';
import 'package:notalone/features/transcript/domain/clock_probe.dart';
import 'package:notalone/features/transcript/domain/transcript_failure.dart';
import 'package:notalone/features/transcript/domain/transcript_timing_config.dart';

/// Ramène les horodatages de tous les invités sur l'horloge de l'hôte
/// (cf. cowork/02-architecture.md §5.1). Sans cela, deux téléphones dont les
/// horloges diffèrent de quelques secondes produiraient un fil dans lequel une
/// réponse précède la question.
///
/// Chaque invité est mesuré par des allers-retours `clock_sync` de type NTP
/// (doc 02 §4) dont on retient la **médiane** : contrairement à la moyenne,
/// elle ignore l'aller-retour qu'un pic de Wi-Fi a ralenti, et c'est
/// exactement ce qui arrive sur le réseau d'un appartement.
///
/// Pur Dart, sans état partagé avec le transport : on lui donne des nombres,
/// il rend un offset (CLAUDE.md règle 3).
class SyncedClock {
  SyncedClock({this.config = const TranscriptTimingConfig()});

  final TranscriptTimingConfig config;

  /// Les `clockProbeCount` dernières sondes par invité. Fenêtre glissante :
  /// les horloges de téléphone dérivent, une re-synchronisation en cours de
  /// repas doit finir par chasser les mesures d'il y a deux heures.
  final Map<String, List<ClockProbe>> _probes = {};

  /// Enregistre un aller-retour et rend l'estimation à jour de cet invité.
  Result<ClockOffset> registerProbe({
    required String participantId,
    required int hostSentMs,
    required int guestReceivedMs,
    required int guestSentMs,
    required int hostReceivedMs,
  }) {
    final probe = ClockProbe(
      hostSentMs: hostSentMs,
      guestReceivedMs: guestReceivedMs,
      guestSentMs: guestSentMs,
      hostReceivedMs: hostReceivedMs,
    );
    if (hostReceivedMs < hostSentMs) {
      return const Result.err(
        ClockProbeInvalidFailure('t3 avant t0 côté hôte'),
      );
    }
    if (guestSentMs < guestReceivedMs) {
      return const Result.err(
        ClockProbeInvalidFailure('t2 avant t1 côté invité'),
      );
    }
    // Le traitement de l'invité ne peut pas durer plus longtemps que
    // l'aller-retour complet : au-delà, une des deux horloges a sauté
    // pendant l'échange et la sonde ne mesure plus rien.
    if (probe.roundTripMs < 0) {
      return const Result.err(
        ClockProbeInvalidFailure('temps de traitement invité incohérent'),
      );
    }

    final probes = _probes.putIfAbsent(participantId, () => <ClockProbe>[])
      ..add(probe);
    if (probes.length > config.clockProbeCount) probes.removeAt(0);
    return Result.ok(_estimate(probes));
  }

  /// Estimation courante, ou `null` si cet invité n'a jamais été mesuré.
  ClockOffset? offsetFor(String participantId) {
    final probes = _probes[participantId];
    return probes == null || probes.isEmpty ? null : _estimate(probes);
  }

  /// `true` quand la série d'échanges prévue est complète : l'offset est
  /// alors mesuré, pas simplement ébauché.
  bool isSynced(String participantId) =>
      (_probes[participantId]?.length ?? 0) >= config.clockProbeCount;

  /// Traduit un horodatage pris sur le téléphone de l'invité en horodatage
  /// de l'horloge hôte — la seule sur laquelle le fil est ordonné.
  ///
  /// Invité inconnu : l'horodatage est **rendu tel quel** plutôt que refusé.
  /// Un segment arrivé avant la fin de la synchronisation vaut mieux mal
  /// placé que perdu : le lecteur est sourd, ce fil est tout ce qu'il a.
  /// [isSynced] dit à l'appelant si la correction est fiable.
  int toHostTimeMs({required String participantId, required int guestTimeMs}) {
    final offset = offsetFor(participantId);
    if (offset == null) return guestTimeMs;
    return (guestTimeMs - offset.offsetMs).round();
  }

  /// Oublie un invité (fin de session, ou départ définitif). Une
  /// reconnexion repart sur une série de sondes neuve : le téléphone a pu
  /// remettre son horloge à l'heure entre-temps.
  void forget(String participantId) => _probes.remove(participantId);

  void clear() => _probes.clear();

  ClockOffset _estimate(List<ClockProbe> probes) {
    final offsets = [for (final probe in probes) probe.offsetMs]..sort();
    final middle = offsets.length ~/ 2;
    final median = offsets.length.isOdd
        ? offsets[middle]
        : (offsets[middle - 1] + offsets[middle]) / 2;
    return ClockOffset(
      offsetMs: median,
      probeCount: probes.length,
      bestRoundTripMs: probes
          .map((probe) => probe.roundTripMs)
          .reduce((a, b) => a < b ? a : b),
    );
  }
}
