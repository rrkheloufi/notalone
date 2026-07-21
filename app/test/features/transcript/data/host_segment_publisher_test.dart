import 'package:flutter_test/flutter_test.dart';
import 'package:notalone/features/capture/domain/transcribed_segment.dart';
import 'package:notalone/features/capture/domain/transcription.dart';
import 'package:notalone/features/transcript/data/host_segment_publisher.dart';
import 'package:notalone/features/transcript/domain/incoming_segment.dart';
import 'package:notalone/features/transcript/domain/merge_transcripts_use_case.dart';
import 'package:notalone/features/transcript/domain/transcript_entry.dart';

TranscribedSegment segment({
  String id = 's1',
  int startMs = 1000,
  int endMs = 2000,
  String text = 'bonjour tout le monde',
  double energyDbfs = -20,
}) => TranscribedSegment(
  segmentId: id,
  tStartMs: startMs,
  tEndMs: endMs,
  energyDbfs: energyDbfs,
  transcription: Transcription(text: text, engine: 'native-test'),
);

void main() {
  late MergeTranscriptsUseCase merge;
  late HostSegmentPublisher publisher;

  setUp(() {
    merge = MergeTranscriptsUseCase();
    publisher = HostSegmentPublisher(merge: merge, participantId: 'h1');
  });

  tearDown(() => merge.dispose());

  test('la voix de l’hôte entre dans la fusion sans passer par le réseau',
      () async {
    final entries = <TranscriptEntry>[];
    merge.entries.listen(entries.add);

    publisher.publish(segment());
    merge.flush();
    await pumpEventQueue();

    expect(entries, hasLength(1));
    expect(entries.single.participantId, 'h1');
    expect(entries.single.text, 'bonjour tout le monde');
  });

  test('ses horodatages ne subissent aucune correction d’horloge', () async {
    // L'horloge de l'hôte **est** la référence : `SyncedClock.toHostTimeMs`
    // rend le temps inchangé pour un participant sans sonde, et l'hôte n'en
    // aura jamais (doc 02 §5.1).
    final entries = <TranscriptEntry>[];
    merge.entries.listen(entries.add);

    publisher.publish(segment(startMs: 12345, endMs: 13000));
    merge.flush();
    await pumpEventQueue();

    expect(entries.single.tStartMs, 12345);
    expect(entries.single.tEndMs, 13000);
    expect(merge.isSynced('h1'), isFalse);
  });

  test('sa voix participe à la déduplication cross-talk comme les autres',
      () async {
    // C'est bien le but : la voix de l'hôte est captée par son micro **et**
    // par ceux de ses voisins (doc 02 §5.3).
    final entries = <TranscriptEntry>[];
    merge.entries.listen(entries.add);

    // Le micro de l'hôte, tout près de sa bouche, l'emporte sur celui du
    // voisin.
    merge.submit(
      const IncomingSegment(
        participantId: 'g1',
        segmentId: 'voisin',
        tStartMs: 1000,
        tEndMs: 2000,
        text: 'bonjour tout le monde',
        energyDb: -35,
        engine: 'native-test',
      ),
    );
    publisher.publish(segment(energyDbfs: -18));
    merge.flush();
    await pumpEventQueue();

    expect(entries, hasLength(1));
    expect(entries.single.participantId, 'h1');
    expect(merge.deduplicatedSegments, 1);
  });

  test('le publieur ne possède pas la fusion', () async {
    await publisher.dispose();

    // Le fil la ferme lui-même : la fermer ici couperait la conversation
    // parce qu'un écran de capture s'est refermé.
    final entries = <TranscriptEntry>[];
    merge.entries.listen(entries.add);
    publisher.publish(segment());
    merge.flush();
    await pumpEventQueue();

    expect(entries, hasLength(1));
  });
}
