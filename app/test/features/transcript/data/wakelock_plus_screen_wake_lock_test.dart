import 'package:flutter_test/flutter_test.dart';
import 'package:notalone/features/transcript/data/wakelock_plus_screen_wake_lock.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';

/// Plateforme substituée à celle du plugin : `extends` et non `implements`,
/// c'est ce que `PlatformInterface.verify` exige.
class _FakeWakelockPlatform extends WakelockPlusPlatformInterface {
  final List<bool> toggles = [];
  Exception? failure;

  @override
  Future<void> toggle({required bool enable}) async {
    final failure = this.failure;
    if (failure != null) throw failure;
    toggles.add(enable);
  }

  @override
  Future<bool> get enabled async => toggles.lastOrNull ?? false;
}

void main() {
  late _FakeWakelockPlatform platform;
  late WakelockPlusScreenWakeLock wakeLock;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    platform = _FakeWakelockPlatform();
    // C'est `wakelockPlusPlatformInstance` qu'il faut réassigner, et non
    // `WakelockPlusPlatformInterface.instance` : la façade la lit une seule
    // fois, à l'initialisation de la variable. Le package expose d'ailleurs
    // ce point d'injection en `@visibleForTesting`, précisément parce que les
    // tests unitaires tournent sur macOS.
    wakelockPlusPlatformInstance = platform;
    wakeLock = WakelockPlusScreenWakeLock();
  });

  test('enable garde l’écran allumé', () async {
    await wakeLock.enable();

    expect(platform.toggles, [true]);
  });

  test('release rend l’écran à l’OS', () async {
    await wakeLock.enable();

    await wakeLock.release();

    expect(platform.toggles, [true, false]);
  });

  test('un verrou refusé par l’OS ne remonte pas', () async {
    platform.failure = Exception('wakelock indisponible');

    // Un écran qui s'éteint est un inconfort ; un fil qui refuse de s'ouvrir
    // parce que le verrou a échoué serait une panne.
    await expectLater(wakeLock.enable(), completes);
    await expectLater(wakeLock.release(), completes);
    expect(platform.toggles, isEmpty);
  });
}
