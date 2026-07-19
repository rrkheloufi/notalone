import 'package:notalone/core/result/result.dart';
import 'package:notalone/features/session/domain/qr_session_payload.dart';

/// Client de session LAN minimal du spike MVP-03. Remplacé par le vrai
/// `GuestClient` (backoff, file d'envoi) en MVP-06.
abstract interface class LanClient {
  /// Se connecte à la session décrite par [payload]. Un dépassement du
  /// timeout produit une `ConnectionTimeoutFailure` (cas R7 : WiFi qui
  /// isole les clients).
  Future<Result<void>> connect(QrSessionPayload payload);

  /// Messages texte reçus de l'hôte.
  Stream<String> get messages;

  /// Émet un événement quand la connexion se ferme (hôte arrêté, réseau).
  Stream<void> get disconnections;

  void send(String text);

  /// Mesure l'aller-retour réseau (ping/pong applicatif).
  Future<Result<Duration>> ping();

  Future<void> disconnect();
}
