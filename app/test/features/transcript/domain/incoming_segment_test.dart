import 'package:flutter_test/flutter_test.dart';
import 'package:notalone/features/transcript/domain/incoming_segment.dart';

IncomingSegment build({
  String participantId = 'p1',
  String segmentId = 's1',
  int tStartMs = 1000,
  int tEndMs = 3400,
  String text = 'Tu peux me passer le sel',
  double energyDb = -8,
  String engine = 'ios_speech_analyzer',
  bool isFinal = true,
}) => IncomingSegment(
  participantId: participantId,
  segmentId: segmentId,
  tStartMs: tStartMs,
  tEndMs: tEndMs,
  text: text,
  energyDb: energyDb,
  engine: engine,
  isFinal: isFinal,
);

void main() {
  test('durationMs mesure la parole, pré-roll exclu', () {
    expect(build().durationMs, 2400);
  });

  test('un segment est final par défaut', () {
    expect(build().isFinal, isTrue);
  });

  test('égalité structurelle sur tous les champs', () {
    expect(build(), build());
    expect(build().hashCode, build().hashCode);

    expect(build(), isNot(build(participantId: 'p2')));
    expect(build(), isNot(build(segmentId: 's2')));
    expect(build(), isNot(build(tStartMs: 1001)));
    expect(build(), isNot(build(tEndMs: 3401)));
    expect(build(), isNot(build(text: 'autre chose')));
    expect(build(), isNot(build(energyDb: -32)));
    expect(build(), isNot(build(engine: 'android_on_device')));
    expect(build(), isNot(build(isFinal: false)));
    expect(build(), isNot(42));
  });

  test('deux captations du même énoncé restent deux segments distincts', () {
    // Même phrase, deux téléphones : ce que la dédup devra arbitrer. Rien dans
    // l'entité elle-même ne les confond.
    final close = build(participantId: 'p-papa', segmentId: 'proche');
    final far = build(
      participantId: 'p-marie',
      segmentId: 'lointain',
      energyDb: -32,
    );

    expect(close, isNot(far));
  });
}
