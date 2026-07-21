/// Niveau de batterie du téléphone qui capte.
///
/// Vit dans `capture/` — aux côtés de `BackgroundCaptureGuard` et de ses
/// exemptions d'optimisation batterie — parce que c'est la capture continue qui
/// vide le téléphone : le risque R1 du doc 03 (« capture + VAD 2 h épuisent les
/// téléphones invités ») est ce que cette mesure existe pour rendre visible.
///
/// Outil externe, donc interface ici et implémentation dans `data/`
/// (CLAUDE.md règle 3).
// L'interface n'existe pas pour son nombre de méthodes mais pour la règle 3 :
// c'est la frontière derrière laquelle `battery_plus` est remplaçable sans
// toucher ni `domain/` ni `presentation/`. Une fonction de premier niveau, elle,
// ne s'injecte pas et ne se remplace pas.
// ignore: one_member_abstracts
abstract interface class BatteryLevelSource {
  /// Pourcentage restant (0–100), ou `null` si la plateforme ne sait pas le
  /// dire. Nul plutôt que zéro : « je ne sais pas » et « batterie vide » ne
  /// déclenchent pas la même alerte chez l'hôte.
  Future<int?> currentLevel();
}
