import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:notalone/features/session/domain/protocol/session_message.dart';
import 'package:notalone/features/session/domain/protocol/session_message_codec.dart';
import 'package:notalone/features/session/domain/session_failure.dart';

const exemplars = <SessionMessage>[
  JoinRequest(name: 'Paul', token: 'a3f9c2e1', appVersion: '1.0.0'),
  JoinAck(participantId: 'p-1', colorIndex: 2, clockOffsetProbe: 171000),
  ClockSync(seq: 3, tHostSentMs: 171234),
  ClockSync(
    seq: 3,
    tHostSentMs: 171234,
    tGuestReceivedMs: 171410,
    tGuestSentMs: 171412,
  ),
  SpeechSegmentDto(
    segmentId: 's-1',
    tStartMs: 1000,
    tEndMs: 3500,
    text: 'Bonjour à tous',
    isFinal: true,
    energyDb: -21.5,
    engine: 'ios_native',
  ),
  MicStatus(state: MicStatusState.active, batteryPct: 87),
  SessionEnd(),
  Ping(seq: 1),
  Pong(seq: 1),
];

String envelope({
  Object? v = SessionMessageCodec.protocolVersion,
  Object? type = 'ping',
  Object? payload = const <String, Object?>{'seq': 1},
}) => jsonEncode({'v': v, 'type': type, 'payload': payload});

void main() {
  test('round-trip encode → decode exact pour chaque type de message', () {
    for (final message in exemplars) {
      final decoded = SessionMessageCodec.decode(
        SessionMessageCodec.encode(message),
      );
      expect(decoded.valueOrNull, message, reason: message.type);
      expect(
        decoded.valueOrNull.runtimeType,
        message.runtimeType,
        reason: message.type,
      );
    }
  });

  test('l enveloppe contient exactement {v, type, payload} et v = 1', () {
    for (final message in exemplars) {
      final json =
          jsonDecode(SessionMessageCodec.encode(message))
              as Map<String, Object?>;
      expect(
        json.keys,
        unorderedEquals(['v', 'type', 'payload']),
        reason: message.type,
      );
      expect(json['v'], SessionMessageCodec.protocolVersion);
      expect(json['type'], message.type);
    }
  });

  test('JSON illisible → Failure typée, jamais d exception', () {
    expect(
      SessionMessageCodec.decode('pas du json {').failureOrNull,
      isA<MessageMalformedFailure>(),
    );
  });

  test('pas un objet JSON → Failure', () {
    expect(
      SessionMessageCodec.decode('[1, 2]').failureOrNull,
      isA<MessageMalformedFailure>(),
    );
  });

  test('v absente ou invalide → Failure', () {
    for (final raw in [
      jsonEncode({
        'type': 'ping',
        'payload': {'seq': 1},
      }),
      envelope(v: '1'),
      envelope(v: 0),
      envelope(v: null),
    ]) {
      expect(
        SessionMessageCodec.decode(raw).failureOrNull,
        isA<MessageMalformedFailure>(),
        reason: raw,
      );
    }
  });

  test('type absent ou invalide → Failure', () {
    for (final raw in [
      jsonEncode({
        'v': 1,
        'payload': {'seq': 1},
      }),
      envelope(type: 42),
      envelope(type: ''),
      envelope(type: null),
    ]) {
      expect(
        SessionMessageCodec.decode(raw).failureOrNull,
        isA<MessageMalformedFailure>(),
        reason: raw,
      );
    }
  });

  test('payload absent ou non-objet → Failure', () {
    for (final raw in [
      jsonEncode({'v': 1, 'type': 'ping'}),
      envelope(payload: [1, 2]),
      envelope(payload: 'seq=1'),
      envelope(payload: null),
    ]) {
      expect(
        SessionMessageCodec.decode(raw).failureOrNull,
        isA<MessageMalformedFailure>(),
        reason: raw,
      );
    }
  });

  test('version supérieure avec champs inconnus partout → accepté', () {
    final raw = jsonEncode({
      'v': 2,
      'type': 'ping',
      'payload': {'seq': 7, 'precision': 'ns'},
      'traceId': 'abc-123',
    });
    expect(SessionMessageCodec.decode(raw).valueOrNull, const Ping(seq: 7));
  });

  test('type inconnu → UnknownMessageTypeFailure porteuse du type', () {
    final decoded = SessionMessageCodec.decode(envelope(type: 'hologram'));
    final failure = decoded.failureOrNull;
    expect(failure, isA<UnknownMessageTypeFailure>());
    expect((failure! as UnknownMessageTypeFailure).messageType, 'hologram');
  });

  test('payload malformé d un type connu → Failure du DTO', () {
    final decoded = SessionMessageCodec.decode(
      envelope(payload: const <String, Object?>{}),
    );
    expect(decoded.failureOrNull, isA<MessageMalformedFailure>());
  });
}
