import 'package:meta/meta.dart';

/// Constantes de temps de la fusion côté hôte (cf. cowork/02-architecture.md
/// §5). Regroupées et injectables plutôt qu'en dur dans la logique
/// (cf. cowork/conventions.md §Style) : les tests rejouent la fenêtre de
/// réordonnancement en millisecondes, et MVP-15 la recalibrera sur un vrai
/// repas. Les seuils de déduplication vivront à part, dans `DedupConfig`
/// (MVP-11) : ils se calibrent sur d'autres mesures.
@immutable
class TranscriptTimingConfig {
  const TranscriptTimingConfig({
    this.clockProbeCount = 5,
    this.reorderWindow = const Duration(milliseconds: 1500),
  });

  /// Échanges `clock_sync` retenus pour estimer l'offset d'un invité. La
  /// médiane de 5 mesures écarte les allers-retours ralentis par le Wi-Fi
  /// sans attendre longtemps à la connexion (doc 02 §4).
  final int clockProbeCount;

  /// Délai d'attente avant de figer une entrée : les latences STT diffèrent
  /// d'un téléphone à l'autre, ce buffer laisse à un segment parti plus tôt
  /// le temps d'arriver. 1,5 s tient dans le budget « parole → affichage
  /// < 2 s » (doc 01 §critères de succès) ; au-delà l'entrée est figée et ne
  /// bougera plus sous les yeux du lecteur (doc 02 §5.2).
  final Duration reorderWindow;

  int get reorderWindowMs => reorderWindow.inMilliseconds;
}
