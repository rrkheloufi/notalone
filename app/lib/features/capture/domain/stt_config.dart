import 'package:meta/meta.dart';

/// Seuils du pipeline de transcription — jamais en dur dans la logique
/// (conventions.md). À recalibrer sur données réelles en MVP-15.
@immutable
class SttConfig {
  const SttConfig({
    this.transcriptionTimeoutMs = 8000,
    this.maxPendingSegments = 8,
  });

  /// Au-delà, le segment est abandonné et la file repart. Large devant la
  /// cible de 1,5 s du critère d'acceptation : ce délai n'est pas un objectif
  /// de latence, c'est le filet qui empêche un moteur muet de figer le fil.
  final int transcriptionTimeoutMs;

  /// Segments en attente au-delà desquels on jette **le plus ancien**. Les
  /// moteurs natifs ne transcrivent qu'un segment à la fois : si la parole
  /// arrive plus vite que la transcription, la file grossirait sans fin (doc
  /// 03 R1 — 2 h de repas). Passé 8 segments de retard, le plus vieux n'a de
  /// toute façon plus sa place dans un fil de conversation.
  final int maxPendingSegments;

  Duration get transcriptionTimeout =>
      Duration(milliseconds: transcriptionTimeoutMs);
}
