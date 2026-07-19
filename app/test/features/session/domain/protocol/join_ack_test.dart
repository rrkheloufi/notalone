import 'package:flutter_test/flutter_test.dart';
import 'package:notalone/features/session/domain/protocol/session_message.dart';
import 'package:notalone/features/session/domain/protocol/session_message_codec.dart';
import 'package:notalone/features/session/domain/session_failure.dart';

const ack = JoinAck(
  participantId: 'p-42',
  colorIndex: 3,
  clockOffsetProbe: 171000,
);

void main() {
  test('payload JSON : exactement les champs du doc 02 §4', () {
    expect(
      ack.toPayloadJson().keys,
      unorderedEquals(['participantId', 'colorIndex', 'clockOffsetProbe']),
    );
  });

  test('round-trip via le codec', () {
    expect(
      SessionMessageCodec.decode(SessionMessageCodec.encode(ack)).valueOrNull,
      ack,
    );
  });

  test('champs inconnus ignorés (tolérance ascendante)', () {
    final payload = ack.toPayloadJson()..['sessionMode'] = 'mirror';
    expect(JoinAck.fromPayload(payload).valueOrNull, ack);
  });

  test('champ manquant → Failure', () {
    for (final missing in ['participantId', 'colorIndex', 'clockOffsetProbe']) {
      final payload = ack.toPayloadJson()..remove(missing);
      expect(
        JoinAck.fromPayload(payload).failureOrNull,
        isA<MessageMalformedFailure>(),
        reason: 'champ manquant : $missing',
      );
    }
  });

  test('types invalides → Failure', () {
    for (final overrides in <Map<String, Object?>>[
      {'participantId': 42},
      {'colorIndex': 'trois'},
      {'clockOffsetProbe': 1.5},
    ]) {
      final payload = ack.toPayloadJson()..addAll(overrides);
      expect(
        JoinAck.fromPayload(payload).failureOrNull,
        isA<MessageMalformedFailure>(),
        reason: 'overrides : $overrides',
      );
    }
  });

  test('participantId vide ou colorIndex négatif → Failure', () {
    for (final overrides in <Map<String, Object?>>[
      {'participantId': ''},
      {'colorIndex': -1},
    ]) {
      final payload = ack.toPayloadJson()..addAll(overrides);
      expect(
        JoinAck.fromPayload(payload).failureOrNull,
        isA<MessageMalformedFailure>(),
        reason: 'overrides : $overrides',
      );
    }
  });

  test('colorIndex 0 accepté', () {
    final payload = ack.toPayloadJson()..['colorIndex'] = 0;
    expect(JoinAck.fromPayload(payload).valueOrNull?.colorIndex, 0);
  });

  test('égalité par valeur', () {
    final other = JoinAck.fromPayload(ack.toPayloadJson()).valueOrNull;
    expect(other, ack);
    expect(other.hashCode, ack.hashCode);
  });
}
