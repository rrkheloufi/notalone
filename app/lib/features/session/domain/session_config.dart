import 'package:meta/meta.dart';

/// Constantes de cycle de vie d'une session hôte (cf. cowork/02-architecture.md
/// §4). Regroupées et injectables plutôt qu'en dur dans le serveur : les tests
/// d'intégration rejouent le keepalive en millisecondes au lieu de secondes
/// (cf. cowork/conventions.md §Style).
@immutable
class SessionConfig {
  const SessionConfig({
    this.maxParticipants = 8,
    this.keepaliveInterval = const Duration(seconds: 5),
    this.missedPongsBeforeDrop = 3,
    this.joinTimeout = const Duration(seconds: 5),
  });

  /// Participants simultanés, **hôte inclus** : il capte sa propre voix comme
  /// les autres (doc 02 §1) et consomme donc une place et une couleur. Doc 01
  /// §5 parle de « 8 invités max » ; la palette locuteurs compte 8 couleurs,
  /// on s'aligne dessus (décision Rayan, 19/07/2026).
  final int maxParticipants;

  /// Période des `ping` émis par l'hôte vers chaque invité.
  final Duration keepaliveInterval;

  /// Pings consécutifs sans `pong` avant de déclarer l'invité déconnecté.
  final int missedPongsBeforeDrop;

  /// Délai laissé à un socket fraîchement accepté pour envoyer un
  /// `join_request` valide, au-delà duquel il est fermé.
  final Duration joinTimeout;
}
