import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notalone/features/capture/data/battery_plus_level_source.dart';

BatteryPlusLevelSource reading(int level) =>
    BatteryPlusLevelSource(readLevel: () async => level);

BatteryPlusLevelSource failing(Exception error) =>
    BatteryPlusLevelSource(readLevel: () async => throw error);

void main() {
  test('un niveau plausible passe tel quel', () async {
    expect(await reading(64).currentLevel(), 64);
  });

  test('les bornes 0 et 100 sont des niveaux valides', () async {
    // Une batterie vide est une information — et même la plus urgente.
    expect(await reading(0).currentLevel(), 0);
    expect(await reading(100).currentLevel(), 100);
  });

  test('une valeur hors bornes ne vaut pas mieux qu’une absence', () async {
    // Simulateur ou poste de dev : `-1` circule, et il ne doit surtout pas
    // être lu comme « batterie vide » par le panneau de supervision.
    for (final absurd in [-1, 101]) {
      expect(
        await reading(absurd).currentLevel(),
        isNull,
        reason: 'niveau $absurd',
      );
    }
  });

  test('plugin absent ou en panne → inconnu, jamais une exception', () async {
    // Ne pas connaître la batterie d'un convive est une information manquante
    // dans un panneau, pas une panne de session.
    for (final error in <Exception>[
      PlatformException(code: 'UNAVAILABLE'),
      MissingPluginException('pas de battery_plus ici'),
    ]) {
      expect(await failing(error).currentLevel(), isNull, reason: '$error');
    }
  });
}
