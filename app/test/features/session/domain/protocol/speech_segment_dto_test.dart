import 'package:flutter_test/flutter_test.dart';
import 'package:notalone/features/session/domain/protocol/session_message.dart';
import 'package:notalone/features/session/domain/protocol/session_message_codec.dart';
import 'package:notalone/features/session/domain/session_failure.dart';

const segment = SpeechSegmentDto(
  segmentId: 's-7',
  tStartMs: 1000,
  tEndMs: 3500,
  text: 'Bonjour à tous',
  isFinal: true,
  energyDb: -21.5,
  engine: 'ios_native',
);

void main() {
  test('payload JSON : exactement les champs du doc 02 §4', () {
    expect(
      segment.toPayloadJson().keys,
      unorderedEquals([
        'segmentId',
        'tStartMs',
        'tEndMs',
        'text',
        'isFinal',
        'energyDb',
        'engine',
      ]),
    );
  });

  test('round-trip via le codec', () {
    expect(
      SessionMessageCodec.decode(
        SessionMessageCodec.encode(segment),
      ).valueOrNull,
      segment,
    );
  });

  test('champs inconnus ignorés (tolérance ascendante)', () {
    final payload = segment.toPayloadJson()..['lang'] = 'fr';
    expect(SpeechSegmentDto.fromPayload(payload).valueOrNull, segment);
  });

  test('energyDb entier (JSON num) accepté et converti en double', () {
    final payload = segment.toPayloadJson()..['energyDb'] = -21;
    final decoded = SpeechSegmentDto.fromPayload(payload).valueOrNull;
    expect(decoded?.energyDb, -21.0);
  });

  test('tEndMs avant tStartMs → Failure ; égalité acceptée', () {
    final inverted = segment.toPayloadJson()..['tEndMs'] = 999;
    expect(
      SpeechSegmentDto.fromPayload(inverted).failureOrNull,
      isA<MessageMalformedFailure>(),
    );
    final flat = segment.toPayloadJson()..['tEndMs'] = 1000;
    expect(SpeechSegmentDto.fromPayload(flat).isOk, isTrue);
  });

  test('text vide accepté (partiel en cours de reconnaissance)', () {
    final payload = segment.toPayloadJson()
      ..['text'] = ''
      ..['isFinal'] = false;
    expect(SpeechSegmentDto.fromPayload(payload).isOk, isTrue);
  });

  test('champ manquant → Failure', () {
    for (final missing in segment.toPayloadJson().keys) {
      final payload = segment.toPayloadJson()..remove(missing);
      expect(
        SpeechSegmentDto.fromPayload(payload).failureOrNull,
        isA<MessageMalformedFailure>(),
        reason: 'champ manquant : $missing',
      );
    }
  });

  test('types invalides → Failure', () {
    for (final overrides in <Map<String, Object?>>[
      {'segmentId': 7},
      {'segmentId': ''},
      {'tStartMs': 'mille'},
      {'tEndMs': 3.5},
      {'text': 42},
      {'isFinal': 'true'},
      {'energyDb': '-21.5'},
      {'engine': 1},
    ]) {
      final payload = segment.toPayloadJson()..addAll(overrides);
      expect(
        SpeechSegmentDto.fromPayload(payload).failureOrNull,
        isA<MessageMalformedFailure>(),
        reason: 'overrides : $overrides',
      );
    }
  });

  test('égalité par valeur', () {
    final other = SpeechSegmentDto.fromPayload(
      segment.toPayloadJson(),
    ).valueOrNull;
    expect(other, segment);
    expect(other.hashCode, segment.hashCode);
  });
}
