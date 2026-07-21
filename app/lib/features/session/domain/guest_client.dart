import 'package:meta/meta.dart';
import 'package:notalone/core/result/failure.dart';
import 'package:notalone/core/result/result.dart';
import 'package:notalone/features/session/domain/protocol/session_message.dart';
import 'package:notalone/features/session/domain/qr_session_payload.dart';

/// Client de session tenu par le téléphone invité : entrée en session,
/// reconnexion automatique en conservant son identité, envoi des messages
/// (cf. cowork/02-architecture.md §4). Comme pour le serveur, le transport
/// est un outil externe : interface en `domain/`, implémentation en `data/`
/// (CLAUDE.md règle 3).
abstract interface class GuestClient {
  /// Se connecte à la session décrite par [session] et demande à entrer sous
  /// [name]. Les tentatives suivantes (reconnexion) sont automatiques.
  Future<Result<GuestSession>> join({
    required QrSessionPayload session,
    required String name,
  });

  Stream<GuestClientEvent> get events;

  /// Identité obtenue de l'hôte, nulle tant qu'aucun `join_ack` n'est arrivé.
  GuestSession? get session;

  /// Envoie un message à l'hôte. Pendant une coupure, le message est mis en
  /// file et part à la reconnexion (cf. `GuestConfig.maxQueuedMessages`).
  void send(SessionMessage message);

  /// Quitte volontairement : plus aucune reconnexion n'est tentée. Le client
  /// reste réutilisable pour un nouveau [join] (rescan après une session
  /// terminée ou perdue).
  Future<void> leave();

  /// Libère définitivement le client et son flux d'événements.
  Future<void> dispose();
}

/// Identité de l'invité dans la session, telle que l'hôte la lui a attribuée
/// dans le `join_ack`. Le [participantId] est conservé d'une reconnexion à
/// l'autre : c'est ce qui rend sa couleur et son historique à un invité qui
/// revient (cf. `JoinRequest.participantId`).
@immutable
class GuestSession {
  const GuestSession({
    required this.participantId,
    required this.colorIndex,
    required this.clockOffsetProbe,
  });

  final String participantId;
  final int colorIndex;

  /// Probe n°0 de la synchronisation d'horloge, exploitée en MVP-09.
  final int clockOffsetProbe;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is GuestSession &&
          other.participantId == participantId &&
          other.colorIndex == colorIndex &&
          other.clockOffsetProbe == clockOffsetProbe);

  @override
  int get hashCode => Object.hash(participantId, colorIndex, clockOffsetProbe);
}

@immutable
sealed class GuestClientEvent {
  const GuestClientEvent();
}

/// Connexion perdue, une nouvelle tentative est programmée dans [delay].
/// [attempt] est numéroté à partir de 1 pour l'affichage.
final class GuestReconnecting extends GuestClientEvent {
  const GuestReconnecting({required this.attempt, required this.delay});

  final int attempt;
  final Duration delay;
}

/// La session a repris, avec la même identité qu'avant la coupure.
final class GuestReconnected extends GuestClientEvent {
  const GuestReconnected(this.session);

  final GuestSession session;
}

/// Backoff épuisé (ou refus définitif de l'hôte) : état terminal, l'invité
/// doit rescanner. [failure] porte la dernière cause d'échec.
final class GuestConnectionLost extends GuestClientEvent {
  const GuestConnectionLost(this.failure);

  final Failure failure;
}

/// `session_end` reçu : l'hôte a clos la session, rien à reconnecter.
final class GuestSessionEnded extends GuestClientEvent {
  const GuestSessionEnded();
}

/// Message applicatif reçu de l'hôte. Les échanges que le client tient
/// lui-même — le `pong` du keepalive et la réponse au `clock_sync` (MVP-11) —
/// n'apparaissent pas ici : les remonter n'aurait servi qu'à retarder la
/// réponse, donc à dégrader la mesure d'horloge.
final class GuestMessageReceived extends GuestClientEvent {
  const GuestMessageReceived(this.message);

  final SessionMessage message;
}
