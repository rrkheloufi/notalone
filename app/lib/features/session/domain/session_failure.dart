import 'package:notalone/core/result/failure.dart';

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
