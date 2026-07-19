import 'package:flutter_test/flutter_test.dart';
import 'package:notalone/features/session/domain/protocol/session_message.dart';
import 'package:notalone/features/session/domain/protocol/session_message_codec.dart';
import 'package:notalone/features/session/domain/session_failure.dart';

const request = JoinRequest(
  name: 'Paul',
  token: 'a3f9c2e1b8d74650',
  appVersion: '1.0.0',
);

void main() {
  test('payload JSON : exactement les champs du doc 02 §4', () {
    expect(
      request.toPayloadJson().keys,
      unorderedEquals(['name', 'token', 'appVersion']),
    );
  });

  test('round-trip via le codec', () {
    expect(
      SessionMessageCodec.decode(
        SessionMessageCodec.encode(request),
      ).valueOrNull,
      request,
    );
  });

  test('champs inconnus ignorés (tolérance ascendante)', () {
    final payload = request.toPayloadJson()..['device'] = 'iPhone 15';
    expect(JoinRequest.fromPayload(payload).valueOrNull, request);
  });

  test('champ manquant → Failure', () {
    for (final missing in ['name', 'token', 'appVersion']) {
      final payload = request.toPayloadJson()..remove(missing);
      expect(
        JoinRequest.fromPayload(payload).failureOrNull,
        isA<MessageMalformedFailure>(),
        reason: 'champ manquant : $missing',
      );
    }
  });

  test('types invalides → Failure', () {
    for (final overrides in <Map<String, Object?>>[
      {'name': 42},
      {'token': true},
      {'appVersion': 1},
    ]) {
      final payload = request.toPayloadJson()..addAll(overrides);
      expect(
        JoinRequest.fromPayload(payload).failureOrNull,
        isA<MessageMalformedFailure>(),
        reason: 'overrides : $overrides',
      );
    }
  });

  test('name ou token vide → Failure', () {
    for (final overrides in <Map<String, Object?>>[
      {'name': ''},
      {'token': ''},
    ]) {
      final payload = request.toPayloadJson()..addAll(overrides);
      expect(
        JoinRequest.fromPayload(payload).failureOrNull,
        isA<MessageMalformedFailure>(),
        reason: 'overrides : $overrides',
      );
    }
  });

  test('appVersion vide accepté (contrainte de type seulement)', () {
    final payload = request.toPayloadJson()..['appVersion'] = '';
    expect(JoinRequest.fromPayload(payload).isOk, isTrue);
  });

  test('égalité par valeur', () {
    final other = JoinRequest.fromPayload(request.toPayloadJson()).valueOrNull;
    expect(other, request);
    expect(other.hashCode, request.hashCode);
  });
}
