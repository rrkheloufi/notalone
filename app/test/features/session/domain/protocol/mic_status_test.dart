import 'package:flutter_test/flutter_test.dart';
import 'package:notalone/features/session/domain/protocol/session_message.dart';
import 'package:notalone/features/session/domain/protocol/session_message_codec.dart';
import 'package:notalone/features/session/domain/session_failure.dart';

const status = MicStatus(state: MicStatusState.active, batteryPct: 87);

void main() {
  test('payload JSON : exactement les champs du doc 02 §4', () {
    expect(
      status.toPayloadJson().keys,
      unorderedEquals(['state', 'batteryPct']),
    );
  });

  test('round-trip via le codec pour chacun des 3 états', () {
    for (final state in MicStatusState.values) {
      final message = MicStatus(state: state, batteryPct: 42);
      expect(
        SessionMessageCodec.decode(
          SessionMessageCodec.encode(message),
        ).valueOrNull,
        message,
        reason: state.name,
      );
    }
  });

  test('champs inconnus ignorés (tolérance ascendante)', () {
    final payload = status.toPayloadJson()..['charging'] = true;
    expect(MicStatus.fromPayload(payload).valueOrNull, status);
  });

  test('état inconnu (futur protocole) → Failure', () {
    final payload = status.toPayloadJson()..['state'] = 'backgrounded';
    expect(
      MicStatus.fromPayload(payload).failureOrNull,
      isA<MessageMalformedFailure>(),
    );
  });

  test('champ manquant → Failure', () {
    for (final missing in ['state', 'batteryPct']) {
      final payload = status.toPayloadJson()..remove(missing);
      expect(
        MicStatus.fromPayload(payload).failureOrNull,
        isA<MessageMalformedFailure>(),
        reason: 'champ manquant : $missing',
      );
    }
  });

  test('types invalides → Failure', () {
    for (final overrides in <Map<String, Object?>>[
      {'state': 1},
      {'batteryPct': 'faible'},
      {'batteryPct': 87.5},
    ]) {
      final payload = status.toPayloadJson()..addAll(overrides);
      expect(
        MicStatus.fromPayload(payload).failureOrNull,
        isA<MessageMalformedFailure>(),
        reason: 'overrides : $overrides',
      );
    }
  });

  test('égalité par valeur', () {
    final other = MicStatus.fromPayload(status.toPayloadJson()).valueOrNull;
    expect(other, status);
    expect(other.hashCode, status.hashCode);
    expect(
      status,
      isNot(const MicStatus(state: MicStatusState.muted, batteryPct: 87)),
    );
  });
}
