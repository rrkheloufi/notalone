import 'package:meta/meta.dart';

/// Un aller-retour `clock_sync` complet, vu depuis l'hôte (doc 02 §4) :
///
/// ```text
///  hôte   t0 ──────────────► t1   invité
///                                 (traitement)
///  hôte   t3 ◄────────────── t2   invité
/// ```
///
/// Les quatre horodatages sont pris sur deux horloges différentes : t0/t3 sur
/// celle de l'hôte, t1/t2 sur celle de l'invité. Volontairement exprimé en
/// nombres et non en `ClockSync` : `transcript/` ne dépend pas du protocole de
/// `session/` (CLAUDE.md règle 3, précédent MVP-08).
@immutable
class ClockProbe {
  const ClockProbe({
    required this.hostSentMs,
    required this.guestReceivedMs,
    required this.guestSentMs,
    required this.hostReceivedMs,
  });

  /// t0 — horloge hôte.
  final int hostSentMs;

  /// t1 — horloge invité.
  final int guestReceivedMs;

  /// t2 — horloge invité.
  final int guestSentMs;

  /// t3 — horloge hôte.
  final int hostReceivedMs;

  /// `((t1−t0) + (t2−t3)) / 2` : de combien l'horloge de l'invité avance sur
  /// celle de l'hôte. Les deux termes portent des erreurs de transmission de
  /// signes opposés, qui s'annulent quand l'aller et le retour durent aussi
  /// longtemps. Reste un `double` : arrondir chaque mesure avant la médiane
  /// ajouterait un biais gratuit.
  double get offsetMs =>
      ((guestReceivedMs - hostSentMs) + (guestSentMs - hostReceivedMs)) / 2;

  /// Temps de transmission aller-retour, temps de traitement de l'invité
  /// retiré. C'est la mesure de qualité de la sonde : plus il est court,
  /// moins l'asymétrie aller/retour peut fausser [offsetMs].
  int get roundTripMs =>
      (hostReceivedMs - hostSentMs) - (guestSentMs - guestReceivedMs);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ClockProbe &&
          other.hostSentMs == hostSentMs &&
          other.guestReceivedMs == guestReceivedMs &&
          other.guestSentMs == guestSentMs &&
          other.hostReceivedMs == hostReceivedMs);

  @override
  int get hashCode =>
      Object.hash(hostSentMs, guestReceivedMs, guestSentMs, hostReceivedMs);
}

/// Estimation courante de l'écart d'horloge d'un invité, telle que la publie
/// `SyncedClock`. [probeCount] et [bestRoundTripMs] disent la confiance à lui
/// accorder — ils serviront au diagnostic de session (MVP-13) et à la
/// calibration terrain (MVP-15).
@immutable
class ClockOffset {
  const ClockOffset({
    required this.offsetMs,
    required this.probeCount,
    required this.bestRoundTripMs,
  });

  /// Médiane des sondes retenues, en millisecondes.
  final double offsetMs;

  final int probeCount;

  /// Meilleur aller-retour observé parmi les sondes retenues.
  final int bestRoundTripMs;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ClockOffset &&
          other.offsetMs == offsetMs &&
          other.probeCount == probeCount &&
          other.bestRoundTripMs == bestRoundTripMs);

  @override
  int get hashCode => Object.hash(offsetMs, probeCount, bestRoundTripMs);
}
