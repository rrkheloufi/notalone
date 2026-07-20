import 'package:meta/meta.dart';
import 'package:notalone/features/capture/domain/speech_segment.dart';
import 'package:notalone/features/capture/domain/transcription.dart';

/// Une prise de parole une fois transcrite — **sans son audio**. C'est le
/// point du pipeline où le buffer PCM est abandonné : au-delà, plus rien ne
/// permet de reconstituer la voix (CLAUDE.md règle 2).
///
/// Ses champs sont exactement ceux du `speech_segment` du doc 02 §4 ; c'est
/// MVP-11 qui les mappera vers le DTO, `capture/` n'important jamais
/// `session/` (précédent MVP-08).
@immutable
class TranscribedSegment {
  const TranscribedSegment({
    required this.segmentId,
    required this.tStartMs,
    required this.tEndMs,
    required this.energyDbfs,
    required this.transcription,
  });

  TranscribedSegment.of(SpeechSegment segment, this.transcription)
    : segmentId = segment.segmentId,
      tStartMs = segment.tStartMs,
      tEndMs = segment.tEndMs,
      energyDbfs = segment.energyDbfs;

  final String segmentId;
  final int tStartMs;
  final int tEndMs;
  final double energyDbfs;
  final Transcription transcription;

  String get text => transcription.text;

  int get durationMs => tEndMs - tStartMs;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TranscribedSegment &&
          other.segmentId == segmentId &&
          other.tStartMs == tStartMs &&
          other.tEndMs == tEndMs &&
          other.energyDbfs == energyDbfs &&
          other.transcription == transcription);

  @override
  int get hashCode =>
      Object.hash(segmentId, tStartMs, tEndMs, energyDbfs, transcription);
}
