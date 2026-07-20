import 'package:flutter_test/flutter_test.dart';
import 'package:notalone/features/capture/data/background_capture_guard_factory.dart';

void main() {
  // La fabrique elle-même dépend de `Platform` et du plugin Android : seul le
  // garde neutre (chemin iOS) est exécutable en CI. Il compte quand même, car
  // c'est lui qui doit laisser passer la capture sans rien exiger.
  group('NoopBackgroundCaptureGuard', () {
    const guard = NoopBackgroundCaptureGuard();

    test('prendre le garde réussit sans condition', () async {
      expect((await guard.acquire()).isOk, isTrue);
    });

    test('le relâcher ne lève rien', () async {
      await expectLater(guard.release(), completes);
    });

    test('rien ne bride la capture, rien à demander', () async {
      expect(await guard.isBatteryOptimizationDisabled(), isTrue);
      await expectLater(guard.requestBatteryOptimizationExemption(), completes);
    });
  });
}
