import 'package:flutter_test/flutter_test.dart';
import 'package:notalone/features/session/domain/protocol/session_message.dart';
import 'package:notalone/features/session/domain/protocol/session_message_codec.dart';
import 'package:notalone/features/session/domain/session_failure.dart';

const probe = ClockSync(seq: 3, tHostSentMs: 171234);
const reply = ClockSync(
  seq: 3,
  tHostSentMs: 171234,
  tGuestReceivedMs: 171410,
  tGuestSentMs: 171412,
);

void main() {
  test('aller (hôte → invité) : payload sans les champs invité', () {
    expect(
      probe.toPayloadJson().keys,
      unorderedEquals(['seq', 'tHostSentMs']),
    );
    expect(probe.isReply, isFalse);
  });

  test('retour (invité → hôte) : payload avec les 4 horodatages', () {
    expect(
      reply.toPayloadJson().keys,
      unorderedEquals([
        'seq',
        'tHostSentMs',
        'tGuestReceivedMs',
        'tGuestSentMs',
      ]),
    );
    expect(reply.isReply, isTrue);
  });

  test('round-trip via le codec : aller et retour', () {
    for (final message in [probe, reply]) {
      expect(
        SessionMessageCodec.decode(
          SessionMessageCodec.encode(message),
        ).valueOrNull,
        message,
      );
    }
  });

  test('champs inconnus ignorés (tolérance ascendante)', () {
    final payload = reply.toPayloadJson()..['precision'] = 'ns';
    expect(ClockSync.fromPayload(payload).valueOrNull, reply);
  });

  test('seq ou tHostSentMs manquant ou invalide → Failure', () {
    for (final payload in <Map<String, Object?>>[
      probe.toPayloadJson()..remove('seq'),
      probe.toPayloadJson()..remove('tHostSentMs'),
      probe.toPayloadJson()..['seq'] = 'trois',
      probe.toPayloadJson()..['tHostSentMs'] = 1.5,
    ]) {
      expect(
        ClockSync.fromPayload(payload).failureOrNull,
        isA<MessageMalformedFailure>(),
        reason: 'payload : $payload',
      );
    }
  });

  test('un seul champ invité présent → Failure', () {
    for (final missing in ['tGuestReceivedMs', 'tGuestSentMs']) {
      final payload = reply.toPayloadJson()..remove(missing);
      expect(
        ClockSync.fromPayload(payload).failureOrNull,
        isA<MessageMalformedFailure>(),
        reason: 'champ manquant : $missing',
      );
    }
  });

  test('champs invité non entiers → Failure', () {
    for (final overrides in <Map<String, Object?>>[
      {'tGuestReceivedMs': 'tard'},
      {'tGuestSentMs': 1.5},
    ]) {
      final payload = reply.toPayloadJson()..addAll(overrides);
      expect(
        ClockSync.fromPayload(payload).failureOrNull,
        isA<MessageMalformedFailure>(),
        reason: 'overrides : $overrides',
      );
    }
  });

  test('égalité par valeur (l aller diffère du retour)', () {
    final other = ClockSync.fromPayload(reply.toPayloadJson()).valueOrNull;
    expect(other, reply);
    expect(other.hashCode, reply.hashCode);
    expect(probe, isNot(reply));
  });
}
