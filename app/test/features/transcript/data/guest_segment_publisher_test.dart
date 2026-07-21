import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:notalone/core/result/result.dart';
import 'package:notalone/features/capture/domain/speech_segment.dart';
import 'package:notalone/features/capture/domain/transcribed_segment.dart';
import 'package:notalone/features/capture/domain/transcription.dart';
import 'package:notalone/features/session/domain/guest_client.dart';
import 'package:notalone/features/session/domain/protocol/session_message.dart';
import 'package:notalone/features/session/domain/qr_session_payload.dart';
import 'package:notalone/features/transcript/data/guest_segment_publisher.dart';

final class _FakeGuestClient implements GuestClient {
  final List<SessionMessage> sent = [];

  @override
  Stream<GuestClientEvent> get events => const Stream.empty();

  @override
  GuestSession? session;

  @override
  Future<Result<GuestSession>> join({
    required QrSessionPayload session,
    required String name,
  }) async => throw UnimplementedError();

  @override
  void send(SessionMessage message) => sent.add(message);

  @override
  Future<void> leave() async {}

  @override
  Future<void> dispose() async {}
}

TranscribedSegment transcribed({
  String segmentId = 's1',
  int tStartMs = 10000,
  int tEndMs = 12400,
  double energyDbfs = -8,
  String text = 'Tu peux me passer le sel',
  String engine = 'ios_speech_analyzer',
  bool isFinal = true,
}) => TranscribedSegment(
  segmentId: segmentId,
  tStartMs: tStartMs,
  tEndMs: tEndMs,
  energyDbfs: energyDbfs,
  transcription: Transcription(text: text, engine: engine, isFinal: isFinal),
);

void main() {
  late _FakeGuestClient client;
  late GuestSegmentPublisher publisher;

  setUp(() {
    client = _FakeGuestClient();
    publisher = GuestSegmentPublisher(client: client);
  });

  test('publie un speech_segment fidèle au segment transcrit', () {
    publisher.publish(transcribed());

    final message = client.sent.single as SpeechSegmentDto;
    expect(message.segmentId, 's1');
    expect(message.tStartMs, 10000);
    expect(message.tEndMs, 12400);
    expect(message.text, 'Tu peux me passer le sel');
    expect(message.energyDb, -8);
    expect(message.engine, 'ios_speech_analyzer');
    expect(message.isFinal, isTrue);
  });

  test('le drapeau isFinal du moteur voyage tel quel', () {
    publisher.publish(transcribed(isFinal: false));

    expect((client.sent.single as SpeechSegmentDto).isFinal, isFalse);
  });

  test('rien de ce qui part ne permet de remonter à la voix', () {
    // Le DTO est fait de nombres et de texte : aucun champ ne peut porter du
    // PCM (CLAUDE.md règle 2). Le segment audio, lui, existe bien en amont.
    final source = SpeechSegment(
      segmentId: 's1',
      tStartMs: 10000,
      tEndMs: 12400,
      energyDbfs: -8,
      samples: Float32List.fromList([0.1, -0.2, 0.3]),
      sampleRate: 16000,
    );
    publisher.publish(
      TranscribedSegment.of(
        source,
        const Transcription(text: 'Bonsoir', engine: 'ios_speech_analyzer'),
      ),
    );

    final json = (client.sent.single as SpeechSegmentDto).toPayloadJson();
    expect(
      json.values.every((value) => value is num || value is String ||
          value is bool),
      isTrue,
    );
  });

  test("chaque segment part séparément, dans l'ordre", () {
    publisher
      ..publish(transcribed(segmentId: 'a'))
      ..publish(transcribed(segmentId: 'b'));

    expect(
      [for (final m in client.sent) (m as SpeechSegmentDto).segmentId],
      ['a', 'b'],
    );
  });
}
