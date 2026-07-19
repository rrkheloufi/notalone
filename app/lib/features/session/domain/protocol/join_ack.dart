part of 'session_message.dart';

/// `join_ack` (hôte → invité) : admission en session. `clockOffsetProbe`
/// est l'horodatage hôte (ms, horloge hôte) à l'émission de l'ack — il sert
/// de probe n°0 à la synchronisation d'horloge (MVP-09).
final class JoinAck extends SessionMessage {
  const JoinAck({
    required this.participantId,
    required this.colorIndex,
    required this.clockOffsetProbe,
  });

  static const wireType = 'join_ack';

  final String participantId;
  final int colorIndex;
  final int clockOffsetProbe;

  @override
  String get type => wireType;

  @override
  Map<String, Object?> toPayloadJson() => {
    'participantId': participantId,
    'colorIndex': colorIndex,
    'clockOffsetProbe': clockOffsetProbe,
  };

  static Result<JoinAck> fromPayload(Map<String, Object?> payload) {
    final participantId = payload['participantId'];
    final colorIndex = payload['colorIndex'];
    final clockOffsetProbe = payload['clockOffsetProbe'];
    if (participantId is! String || participantId.isEmpty) {
      return const Result.err(
        MessageMalformedFailure('join_ack : participantId absent'),
      );
    }
    if (colorIndex is! int || colorIndex < 0) {
      return const Result.err(
        MessageMalformedFailure('join_ack : colorIndex invalide'),
      );
    }
    if (clockOffsetProbe is! int) {
      return const Result.err(
        MessageMalformedFailure('join_ack : clockOffsetProbe absent'),
      );
    }
    return Result.ok(
      JoinAck(
        participantId: participantId,
        colorIndex: colorIndex,
        clockOffsetProbe: clockOffsetProbe,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is JoinAck &&
          other.participantId == participantId &&
          other.colorIndex == colorIndex &&
          other.clockOffsetProbe == clockOffsetProbe);

  @override
  int get hashCode => Object.hash(participantId, colorIndex, clockOffsetProbe);
}
