import 'package:notalone/features/transcript/domain/screen_wake_lock.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Verrou d'écran via `wakelock_plus`. Retenu parce qu'il est le seul du lot à
/// livrer un `Package.swift` pour iOS : le projet est passé à Swift Package
/// Manager en MVP-02, et MVP-08 a montré qu'un plugin resté au seul podspec
/// suffit à faire régénérer un Podfile et à casser le build iPhone.
///
/// Les échecs sont avalés à dessein : l'écran qui s'éteint est un inconfort,
/// un fil qui refuse de s'ouvrir est une panne.
class WakelockPlusScreenWakeLock implements ScreenWakeLock {
  @override
  Future<void> enable() async {
    try {
      await WakelockPlus.enable();
    } on Exception {
      return;
    }
  }

  @override
  Future<void> release() async {
    try {
      await WakelockPlus.disable();
    } on Exception {
      return;
    }
  }
}
