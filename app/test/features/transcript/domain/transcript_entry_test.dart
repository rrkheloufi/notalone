import 'package:flutter_test/flutter_test.dart';
import 'package:notalone/features/transcript/domain/transcript_entry.dart';

TranscriptEntry entry({
  String segmentId = 's1',
  String participantId = 'p1',
  String text = 'Bonsoir',
  int tStartMs = 1000,
  int tEndMs = 2000,
  double energyDb = -8,
  String engine = 'ios_speech_analyzer',
  bool isLate = false,
  List<String> mergedSegmentIds = const [],
}) => TranscriptEntry(
  segmentId: segmentId,
  participantId: participantId,
  text: text,
  tStartMs: tStartMs,
  tEndMs: tEndMs,
  energyDb: energyDb,
  engine: engine,
  isLate: isLate,
  mergedSegmentIds: mergedSegmentIds,
);

void main() {
  test('durationMs et duplicateCount', () {
    expect(entry().durationMs, 1000);
    expect(entry().duplicateCount, 0);
    expect(entry(mergedSegmentIds: const ['a', 'b']).duplicateCount, 2);
  });

  test('égalité structurelle, doublons absorbés compris', () {
    expect(entry(), entry());
    expect(entry().hashCode, entry().hashCode);
    expect(entry(), isNot(entry(text: 'Bonjour')));
    expect(entry(), isNot(entry(isLate: true)));
    expect(entry(), isNot(entry(mergedSegmentIds: const ['a'])));
    expect(
      entry(mergedSegmentIds: const ['a', 'b']),
      isNot(entry(mergedSegmentIds: const ['b', 'a'])),
    );
    expect(
      entry(mergedSegmentIds: const ['a']),
      entry(mergedSegmentIds: const ['a']),
    );
  });

  test('toString dit qui, quand, quoi — et ce qui a été absorbé', () {
    final text = entry(
      participantId: 'p-papa',
      mergedSegmentIds: const ['echo'],
      isLate: true,
    ).toString();

    expect(text, contains('p-papa'));
    expect(text, contains('Bonsoir'));
    expect(text, contains('1 doublon'));
    expect(text, contains('tardive'));
  });
}
