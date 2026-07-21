import 'package:meta/meta.dart';

/// Seuils du panneau de supervision de l'hôte (cf. cowork/01-cadrage-produit.md
/// §7.5). Regroupés et injectables plutôt qu'en dur, comme `VadConfig` et
/// `DedupConfig` (cf. cowork/conventions.md §Style).
@immutable
class SupervisionConfig {
  const SupervisionConfig({
    this.lowBatteryThresholdPct = 20,
    this.batteryRefreshInterval = const Duration(seconds: 30),
  });

  /// En deçà (inclus), l'invité est signalé « batterie faible ». 20 % laisse
  /// environ une demi-heure sur un téléphone en capture continue — de quoi
  /// finir un plat, pas un repas : c'est le moment utile pour proposer un
  /// chargeur, et le risque R1 du doc 03 que cette alerte existe pour couvrir.
  final int lowBatteryThresholdPct;

  /// Période de réémission du `mic_status` à niveau de batterie constant. Un
  /// changement d'état du micro, lui, part immédiatement : c'est lui que le
  /// critère « visible chez l'hôte < 10 s » vise, la batterie ne bouge pas à
  /// cette échelle.
  final Duration batteryRefreshInterval;
}
