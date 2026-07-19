part of 'session_message.dart';

/// `join_request` (invité → hôte) : demande d'entrée en session. Le token
/// est celui du QR — c'est ici qu'il est vérifié par l'hôte (MVP-05), pas
/// seulement à l'upgrade WebSocket comme dans le spike MVP-03.
final class JoinRequest extends SessionMessage {
  const JoinRequest({
    required this.name,
    required this.token,
    required this.appVersion,
  });

  static const wireType = 'join_request';

  final String name;
  final String token;
  final String appVersion;

  @override
  String get type => wireType;

  @override
  Map<String, Object?> toPayloadJson() => {
    'name': name,
    'token': token,
    'appVersion': appVersion,
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
    return Result.ok(
      JoinRequest(name: name, token: token, appVersion: appVersion),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is JoinRequest &&
          other.name == name &&
          other.token == token &&
          other.appVersion == appVersion);

  @override
  int get hashCode => Object.hash(name, token, appVersion);
}
