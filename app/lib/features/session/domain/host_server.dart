import 'package:meta/meta.dart';
import 'package:notalone/core/result/result.dart';
import 'package:notalone/features/session/domain/participant.dart';
import 'package:notalone/features/session/domain/protocol/session_message.dart';

/// Serveur de session tenu par le téléphone hôte : admission des invités,
/// registre des participants, keepalive, diffusion et fin de session
/// (cf. cowork/02-architecture.md §4). Le transport est un outil externe :
/// interface en `domain/`, implémentation en `data/` (CLAUDE.md règle 3).
abstract interface class HostServer {
  /// Démarre sur un port éphémère, inscrit l'hôte sous [hostName] et retourne
  /// de quoi construire le QR.
  Future<Result<HostServerInfo>> start({required String hostName});

  Stream<HostServerEvent> get events;

  /// Participants connus, connectés ou en attente de reconnexion.
  List<Participant> get participants;

  /// Diffuse un message à tous les invités connectés.
  void broadcast(SessionMessage message);

  /// Envoie un message au seul invité visé, s'il est connecté.
  void sendTo(String participantId, SessionMessage message);

  /// Diffuse `session_end`, ferme toutes les connexions et efface l'état.
  /// Terminal : une nouvelle session passe par un nouveau [HostServer].
  Future<void> endSession();
}

/// Coordonnées de la session démarrée + identité locale de l'hôte.
@immutable
class HostServerInfo {
  const HostServerInfo({
    required this.host,
    required this.port,
    required this.token,
    required this.hostParticipant,
  });

  final String host;
  final int port;
  final String token;
  final Participant hostParticipant;
}

@immutable
sealed class HostServerEvent {
  const HostServerEvent();
}

/// Invité admis. [isReconnection] distingue un retour (identité et couleur
/// conservées) d'une première entrée, pour l'UI de l'hôte (MVP-06/13).
final class ParticipantJoined extends HostServerEvent {
  const ParticipantJoined({
    required this.participant,
    required this.isReconnection,
  });

  final Participant participant;
  final bool isReconnection;
}

/// Entrée refusée : token invalide, session pleine ou `join_request`
/// inexploitable. [closeCode] est celui envoyé à l'invité
/// (cf. `SessionCloseCodes`).
final class ParticipantRejected extends HostServerEvent {
  const ParticipantRejected({required this.reason, required this.closeCode});

  final String reason;
  final int closeCode;
}

/// Invité parti : socket fermé ou keepalive expiré. Son identité et sa
/// couleur lui restent réservées pour une reconnexion.
final class ParticipantDisconnected extends HostServerEvent {
  const ParticipantDisconnected(this.participant);

  final Participant participant;
}

/// Message applicatif reçu d'un invité admis (`speech_segment`, `mic_status`,
/// `clock_sync`…). Les `ping`/`pong` du keepalive sont traités par le serveur
/// et n'apparaissent pas ici.
final class SessionMessageReceived extends HostServerEvent {
  const SessionMessageReceived({
    required this.participantId,
    required this.message,
  });

  final String participantId;
  final SessionMessage message;
}
