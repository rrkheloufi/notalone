part of 'session_message.dart';

/// `ping`/`pong` : keepalive bidirectionnel (5 s, 3 échecs = déconnecté,
/// MVP-05). `seq` apparie chaque pong à son ping et permet la mesure de RTT.
final class Ping extends SessionMessage {
  const Ping({required this.seq});

  static const wireType = 'ping';

  final int seq;

  @override
  String get type => wireType;

  @override
  Map<String, Object?> toPayloadJson() => {'seq': seq};

  static Result<Ping> fromPayload(Map<String, Object?> payload) {
    final seq = payload['seq'];
    if (seq is! int) {
      return const Result.err(MessageMalformedFailure('ping : seq absent'));
    }
    return Result.ok(Ping(seq: seq));
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Ping && other.seq == seq);

  @override
  int get hashCode => Object.hash(Ping, seq);
}

final class Pong extends SessionMessage {
  const Pong({required this.seq});

  static const wireType = 'pong';

  final int seq;

  @override
  String get type => wireType;

  @override
  Map<String, Object?> toPayloadJson() => {'seq': seq};

  static Result<Pong> fromPayload(Map<String, Object?> payload) {
    final seq = payload['seq'];
    if (seq is! int) {
      return const Result.err(MessageMalformedFailure('pong : seq absent'));
    }
    return Result.ok(Pong(seq: seq));
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Pong && other.seq == seq);

  @override
  int get hashCode => Object.hash(Pong, seq);
}
