import 'package:flutter_test/flutter_test.dart';
import 'package:notalone/features/session/domain/protocol/session_message.dart';
import 'package:notalone/features/session/domain/protocol/session_message_codec.dart';
import 'package:notalone/features/session/domain/session_failure.dart';

void main() {
  test('payload JSON : exactement {seq}', () {
    expect(const Ping(seq: 5).toPayloadJson(), {'seq': 5});
    expect(const Pong(seq: 5).toPayloadJson(), {'seq': 5});
  });

  test('round-trip via le codec', () {
    for (final message in const <SessionMessage>[Ping(seq: 5), Pong(seq: 5)]) {
      final decoded = SessionMessageCodec.decode(
        SessionMessageCodec.encode(message),
      );
      expect(decoded.valueOrNull, message);
      expect(decoded.valueOrNull.runtimeType, message.runtimeType);
    }
  });

  test('champs inconnus ignorés (tolérance ascendante)', () {
    expect(
      Ping.fromPayload({'seq': 5, 'tSentMs': 171000}).valueOrNull,
      const Ping(seq: 5),
    );
    expect(
      Pong.fromPayload({'seq': 5, 'tSentMs': 171000}).valueOrNull,
      const Pong(seq: 5),
    );
  });

  test('seq manquant ou invalide → Failure', () {
    for (final payload in <Map<String, Object?>>[
      {},
      {'seq': 'cinq'},
      {'seq': 5.0},
      {'seq': null},
    ]) {
      expect(
        Ping.fromPayload(payload).failureOrNull,
        isA<MessageMalformedFailure>(),
        reason: 'ping, payload : $payload',
      );
      expect(
        Pong.fromPayload(payload).failureOrNull,
        isA<MessageMalformedFailure>(),
        reason: 'pong, payload : $payload',
      );
    }
  });

  test('un ping n est jamais égal à un pong (types wire distincts)', () {
    expect(const Ping(seq: 5), isNot(const Pong(seq: 5)));
    expect(const Ping(seq: 5), const Ping(seq: 5));
    expect(const Pong(seq: 5), const Pong(seq: 5));
    expect(const Ping(seq: 5).hashCode, const Ping(seq: 5).hashCode);
    expect(const Pong(seq: 5).hashCode, const Pong(seq: 5).hashCode);
    expect(const Ping(seq: 5).hashCode, isNot(const Pong(seq: 5).hashCode));
  });
}
