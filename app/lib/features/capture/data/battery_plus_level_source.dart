import 'package:battery_plus/battery_plus.dart';
import 'package:notalone/features/capture/domain/battery_level_source.dart';

/// Lecture brute du niveau de batterie, telle que la plateforme la rend.
typedef BatteryLevelReader = Future<int> Function();

Future<int> _readFromPlugin() => Battery().batteryLevel;

/// [BatteryLevelSource] adossé à `battery_plus`.
///
/// Vérifié avant de retenir le package, comme l'exige la leçon de MVP-08
/// (`flutter_foreground_task`, podspec seul → Podfile régénéré → build iPhone
/// cassé) : `battery_plus` livre bien `ios/battery_plus/Package.swift`, donc
/// rien ne réintroduit CocoaPods dans le projet.
///
/// C'est la **lecture** qui est injectable, et non un objet `Battery` :
/// celui-ci est un singleton à constructeur privé, l'injecter ne permettrait
/// de tester rien du tout. La frontière remplaçable reste
/// [BatteryLevelSource] (CLAUDE.md règle 3) ; ce paramètre ne sert qu'à mettre
/// sous test la politique de ce fichier — bornes et pannes.
class BatteryPlusLevelSource implements BatteryLevelSource {
  const BatteryPlusLevelSource({this._readLevel = _readFromPlugin});

  final BatteryLevelReader _readLevel;

  @override
  Future<int?> currentLevel() async {
    try {
      final level = await _readLevel();
      // Une plateforme sans batterie (simulateur, poste de dev) rend parfois
      // une valeur hors bornes : elle ne vaut pas mieux qu'une absence, et
      // surtout elle ne doit pas se lire « batterie vide » chez l'hôte.
      return level < 0 || level > 100 ? null : level;
    } on Exception {
      // `PlatformException` et `MissingPluginException` implémentent toutes
      // deux `Exception` : le plugin absent d'un test est traité comme une
      // plateforme sans batterie.
      return null;
    }
  }
}
