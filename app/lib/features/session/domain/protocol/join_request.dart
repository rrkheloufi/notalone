part of 'session_message.dart';

/// `join_request` (invité → hôte) : demande d'entrée en session. Le token
/// est celui du QR — c'est ici qu'il est vérifié par l'hôte (MVP-05), pas
/// seulement à l'upgrade WebSocket comme dans le spike MVP-03.
///
/// [participantId] est absent au premier join et repris de la `join_ack`
/// lors d'une reconnexion : c'est ce qui rend son identité et sa couleur à
/// un invité qui revient (MVP-05, amendement validé par Rayan le
/// 19/07/2026). Comme l'ID est un aléatoire 128 bits, il fait aussi office
/// de jeton de reprise : un autre téléphone ne peut pas usurper une place
/// en déclarant simplement le même prénom.
final class JoinRequest extends SessionMessage {
  const JoinRequest({
    required this.name,
    required this.token,
    required this.appVersion,
    this.participantId,
  });

  static const wireType = 'join_request';

  final String name;
  final String token;
  final String appVersion;
  final String? participantId;

  @override
  String get type => wireType;

  @override
  Map<String, Object?> toPayloadJson() => {
    'name': name,
    'token': token,
    'appVersion': appVersion,
    if (participantId != null) 'participantId': participantId,
  };

  static Result<JoinRequest> fromPayload(Map<String, Object?> payload) {
    final name = payload['name'];
    final token = payload['token'];
    final appVersion = payload['appVersion'];
    if (name is! String || name.isEmpty) {
      return const Result.err(
        MessageMalformedFailure('join_request : name absent'),
      );
    }
    if (token is! String || token.isEmpty) {
      return const Result.err(
        MessageMalformedFailure('join_request : token absent'),
      );
    }
    if (appVersion is! String) {
      return const Result.err(
        MessageMalformedFailure('join_request : appVersion absent'),
      );
    }
    final participantId = payload['participantId'];
    if (participantId != null &&
        (participantId is! String || participantId.isEmpty)) {
      return const Result.err(
        MessageMalformedFailure('join_request : participantId invalide'),
      );
    }
    return Result.ok(
      JoinRequest(
        name: name,
        token: token,
        appVersion: appVersion,
        participantId: participantId as String?,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is JoinRequest &&
          other.name == name &&
          other.token == token &&
          other.appVersion == appVersion &&
          other.participantId == participantId);

  @override
  int get hashCode => Object.hash(name, token, appVersion, participantId);
}
