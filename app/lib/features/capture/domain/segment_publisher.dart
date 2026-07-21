import 'package:notalone/features/capture/domain/transcribed_segment.dart';

/// Où part un segment une fois transcrit. Interface parce que la destination
/// est un outil externe (CLAUDE.md règle 3) et qu'elle change selon qui capte :
/// l'invité l'envoie sur le fil WebSocket, l'hôte la remet directement à sa
/// propre fusion (MVP-13), et l'écran « mon micro » ouvert hors session n'en a
/// aucune.
///
/// C'est aussi ce qui permet à `capture/` de ne jamais importer `session/`
/// (précédent MVP-08) : l'implémentation qui connaît les deux vit ailleurs.
abstract interface class SegmentPublisher {
  void publish(TranscribedSegment segment);

  Future<void> dispose();
}
