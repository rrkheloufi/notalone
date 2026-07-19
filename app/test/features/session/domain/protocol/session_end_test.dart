import 'package:flutter_test/flutter_test.dart';
import 'package:notalone/features/session/domain/protocol/session_message.dart';
import 'package:notalone/features/session/domain/protocol/session_message_codec.dart';

void main() {
  test('payload vide (doc 02 §4 : « — »)', () {
    expect(const SessionEnd().toPayloadJson(), isEmpty);
  });

  test('round-trip via le codec', () {
    expect(
      SessionMessageCodec.decode(
        SessionMessageCodec.encode(const SessionEnd()),
      ).valueOrNull,
      const SessionEnd(),
    );
  });

  test('champs inconnus ignorés (tolérance ascendante)', () {
    final decoded = SessionEnd.fromPayload({'reason': 'host_left'});
    expect(decoded.valueOrNull, const SessionEnd());
  });

  test('égalité par valeur (toutes les instances sont égales)', () {
    expect(const SessionEnd(), SessionEnd.fromPayload({}).valueOrNull);
    expect(
      const SessionEnd().hashCode,
      SessionEnd.fromPayload({}).valueOrNull.hashCode,
    );
  });

  test('jamais égal à un autre type de message', () {
    const SessionMessage end = SessionEnd();
    const SessionMessage ping = Ping(seq: 1);
    expect(end == ping, isFalse);
  });
}
