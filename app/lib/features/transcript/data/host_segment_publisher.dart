import 'package:notalone/features/capture/domain/segment_publisher.dart';
import 'package:notalone/features/capture/domain/transcribed_segment.dart';
import 'package:notalone/features/transcript/domain/incoming_segment.dart';
import 'package:notalone/features/transcript/domain/merge_transcripts_use_case.dart';

/// Met les segments transcrits de **l'hôte lui-même** sur le fil, sans réseau.
///
/// L'hôte capte sa propre voix comme les autres convives (doc 02 §1), mais il
/// n'a pas de socket vers lui-même : ses segments entrent directement dans la
/// fusion, là où ceux des invités passent par `speech_segment` puis
/// `HostTranscriptBinder`. Une fois dedans, ils sont traités à égalité —
/// déduplication cross-talk comprise, ce qui est bien le but : la voix de
/// l'hôte est captée par son micro **et** par ceux de ses voisins.
///
/// Aucune correction d'horloge à faire : ces horodatages sont déjà pris sur
/// l'horloge de l'hôte, qui est la référence. `SyncedClock.toHostTimeMs` rend
/// justement le temps inchangé pour un participant sans sonde — l'hôte n'en a
/// aucune, et n'en aura jamais.
class HostSegmentPublisher implements SegmentPublisher {
  const HostSegmentPublisher({
    required this._merge,
    required this._participantId,
  });

  final MergeTranscriptsUseCase _merge;

  /// Identité de l'hôte dans son propre registre (`registerHost`) : c'est elle
  /// qui donne à ses bulles son prénom et sa couleur, via l'annuaire.
  final String _participantId;

  @override
  void publish(TranscribedSegment segment) => _merge.submit(
    IncomingSegment(
      participantId: _participantId,
      segmentId: segment.segmentId,
      tStartMs: segment.tStartMs,
      tEndMs: segment.tEndMs,
      text: segment.text,
      energyDb: segment.energyDbfs,
      engine: segment.transcription.engine,
      isFinal: segment.transcription.isFinal,
    ),
  );

  /// La fusion appartient au fil, qui la ferme : le publieur ne possède rien.
  @override
  Future<void> dispose() async {}
}
