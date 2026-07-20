import 'package:meta/meta.dart';
import 'package:notalone/core/result/failure.dart';
import 'package:notalone/features/session/domain/protocol/session_close_codes.dart';

sealed class SessionFailure extends Failure {
  const SessionFailure(super.message);
}

final class QrPayloadMalformedFailure extends SessionFailure {
  const QrPayloadMalformedFailure(String details)
    : super('Payload QR invalide : $details');
}

final class ServerStartFailure extends SessionFailure {
  const ServerStartFailure(String details)
    : super('Démarrage du serveur : $details');
}

/// Connexion impossible dans le délai imparti : symptôme typique d'un WiFi
/// qui isole les clients entre eux (R7, cf. cowork/03-risques-rgpd-roadmap.md
/// §1) — l'UI propose alors le partage de connexion de l'hôte.
final class ConnectionTimeoutFailure extends SessionFailure {
  const ConnectionTimeoutFailure() : super('Connexion à l hôte expirée');
}

final class ConnectionFailure extends SessionFailure {
  const ConnectionFailure(String details) : super('Connexion : $details');
}

final class MessageMalformedFailure extends SessionFailure {
  const MessageMalformedFailure(String details)
    : super('Message invalide : $details');
}

/// Session complète : la limite du `SessionConfig` compte l'hôte, qui capte
/// sa propre voix comme les autres (doc 02 §1).
final class SessionFullFailure extends SessionFailure {
  const SessionFullFailure(this.maxParticipants)
    : super('Session complète ($maxParticipants participants maximum)');

  final int maxParticipants;
}

/// Token du `join_request` différent de celui du QR : QR périmé d'une session
/// précédente, ou tentative d'entrée non sollicitée.
final class InvalidTokenFailure extends SessionFailure {
  const InvalidTokenFailure() : super('Code de session invalide');
}

/// Entrée refusée par l'hôte, qui exprime son refus par le code de fermeture
/// WebSocket (cf. `SessionCloseCodes`) plutôt que par un message dédié. Le
/// code est conservé pour que l'UI adapte son texte et décide s'il vaut la
/// peine de retenter.
@immutable
final class JoinRefusedFailure extends SessionFailure {
  JoinRefusedFailure(this.closeCode) : super(_messageFor(closeCode));

  final int closeCode;

  static String _messageFor(int closeCode) => switch (closeCode) {
    SessionCloseCodes.invalidToken =>
      'Ce QR code ne correspond plus à la session en cours',
    SessionCloseCodes.sessionFull => 'La session est complète',
    SessionCloseCodes.joinExpected => 'L hôte n a pas compris la demande',
    SessionCloseCodes.sessionEnded => 'La session est terminée',
    _ => 'Entrée refusée par l hôte (code $closeCode)',
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is JoinRefusedFailure && other.closeCode == closeCode);

  @override
  int get hashCode => Object.hash(JoinRefusedFailure, closeCode);
}

/// Enregistrement TXT d'une annonce mDNS inexploitable : version absente,
/// token manquant, hôte non résolu.
final class DiscoveryRecordMalformedFailure extends SessionFailure {
  const DiscoveryRecordMalformedFailure(String details)
    : super('Annonce de session invalide : $details');
}

/// Annonce ou découverte mDNS indisponible (permission réseau local refusée,
/// service système absent). Jamais bloquant : le QR reste le chemin nominal.
final class DiscoveryUnavailableFailure extends SessionFailure {
  const DiscoveryUnavailableFailure(String details)
    : super('Découverte réseau indisponible : $details');
}

/// Type absent de la table du codec : corruption ou message d'une version
/// future — l'appelant peut l'ignorer sans le confondre avec un message
/// corrompu (tolérance ascendante, cf. cowork/02-architecture.md §4).
final class UnknownMessageTypeFailure extends SessionFailure {
  const UnknownMessageTypeFailure(this.messageType)
    : super('Type de message inconnu : $messageType');

  final String messageType;
}
