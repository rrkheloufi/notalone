part of 'session_message.dart';

/// `session_end` (hôte → tous) : fin de session, chaque client efface tout
/// (transcript éphémère, CLAUDE.md règle 5). Payload vide.
final class SessionEnd extends SessionMessage {
  const SessionEnd();

  static const wireType = 'session_end';

  @override
  String get type => wireType;

  @override
  Map<String, Object?> toPayloadJson() => const {};

  static Result<SessionEnd> fromPayload(Map<String, Object?> payload) =>
      const Result.ok(SessionEnd());

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is SessionEnd;

  @override
  int get hashCode => (SessionEnd).hashCode;
}
