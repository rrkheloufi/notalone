part of 'session_message.dart';

/// `speech_segment` (invité → hôte) : segment transcrit. Suffixé `Dto` pour
/// ne pas entrer en collision avec l'entité `SpeechSegment` de capture
/// (MVP-08). `engine` reste une chaîne libre : les moteurs STT sont amenés
/// à changer sans casser le protocole.
final class SpeechSegmentDto extends SessionMessage {
  const SpeechSegmentDto({
    required this.segmentId,
    required this.tStartMs,
    required this.tEndMs,
    required this.text,
    required this.isFinal,
    required this.energyDb,
    required this.engine,
  });

  static const wireType = 'speech_segment';

  final String segmentId;
  final int tStartMs;
  final int tEndMs;
  final String text;
  final bool isFinal;
  final double energyDb;
  final String engine;

  @override
  String get type => wireType;

  @override
  Map<String, Object?> toPayloadJson() => {
    'segmentId': segmentId,
    'tStartMs': tStartMs,
    'tEndMs': tEndMs,
    'text': text,
    'isFinal': isFinal,
    'energyDb': energyDb,
    'engine': engine,
  };

  static Result<SpeechSegmentDto> fromPayload(Map<String, Object?> payload) {
    final segmentId = payload['segmentId'];
    final tStartMs = payload['tStartMs'];
    final tEndMs = payload['tEndMs'];
    final text = payload['text'];
    final isFinal = payload['isFinal'];
    final energyDb = payload['energyDb'];
    final engine = payload['engine'];
    if (segmentId is! String || segmentId.isEmpty) {
      return const Result.err(
        MessageMalformedFailure('speech_segment : segmentId absent'),
      );
    }
    if (tStartMs is! int || tEndMs is! int) {
      return const Result.err(
        MessageMalformedFailure('speech_segment : horodatages absents'),
      );
    }
    if (tEndMs < tStartMs) {
      return const Result.err(
        MessageMalformedFailure('speech_segment : tEndMs avant tStartMs'),
      );
    }
    if (text is! String) {
      return const Result.err(
        MessageMalformedFailure('speech_segment : text absent'),
      );
    }
    if (isFinal is! bool) {
      return const Result.err(
        MessageMalformedFailure('speech_segment : isFinal absent'),
      );
    }
    if (energyDb is! num) {
      return const Result.err(
        MessageMalformedFailure('speech_segment : energyDb absent'),
      );
    }
    if (engine is! String) {
      return const Result.err(
        MessageMalformedFailure('speech_segment : engine absent'),
      );
    }
    return Result.ok(
      SpeechSegmentDto(
        segmentId: segmentId,
        tStartMs: tStartMs,
        tEndMs: tEndMs,
        text: text,
        isFinal: isFinal,
        energyDb: energyDb.toDouble(),
        engine: engine,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SpeechSegmentDto &&
          other.segmentId == segmentId &&
          other.tStartMs == tStartMs &&
          other.tEndMs == tEndMs &&
          other.text == text &&
          other.isFinal == isFinal &&
          other.energyDb == energyDb &&
          other.engine == engine);

  @override
  int get hashCode => Object.hash(
    segmentId,
    tStartMs,
    tEndMs,
    text,
    isFinal,
    energyDb,
    engine,
  );
}
