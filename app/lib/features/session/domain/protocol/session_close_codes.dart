/// Codes de fermeture WebSocket applicatifs (plage privée 4000-4999) par
/// lesquels l'hôte refuse un invité. Le protocole n'a pas de message
/// `join_reject` : la fermeture *est* le refus, et son code dit pourquoi —
/// l'invité (MVP-06) le traduit en message lisible (décision Rayan,
/// 19/07/2026).
abstract final class SessionCloseCodes {
  /// Token du `join_request` invalide.
  static const int invalidToken = 4001;

  /// Session pleine (cf. `SessionConfig.maxParticipants`).
  static const int sessionFull = 4002;

  /// Aucun `join_request` exploitable dans le délai imparti : premier message
  /// d'un autre type, payload malformé, ou silence.
  static const int joinExpected = 4003;

  /// Fin de session décidée par l'hôte, après diffusion du `session_end`.
  static const int sessionEnded = 4004;
}
