import 'dart:io';

import 'package:notalone/core/result/result.dart';
import 'package:notalone/features/capture/data/foreground_service_capture_guard.dart';
import 'package:notalone/features/capture/domain/background_capture_guard.dart';

/// **Seul endroit du projet qui distingue Android d'iOS** pour la capture
/// (CLAUDE.md règle 7), parce que les deux OS n'exigent pas la même chose :
/// Android réclame un foreground service, iOS se contente de
/// `UIBackgroundModes: audio` et de la session `AVAudioSession` que `record`
/// active déjà — il n'y a donc rien à tenir en plus de ce côté.
BackgroundCaptureGuard createBackgroundCaptureGuard({
  required String notificationTitle,
  required String notificationText,
}) => Platform.isAndroid
    ? ForegroundServiceCaptureGuard(
        notificationTitle: notificationTitle,
        notificationText: notificationText,
      )
    : const NoopBackgroundCaptureGuard();

/// Garde neutre : l'OS n'a besoin de rien de particulier pour laisser la
/// capture continuer.
class NoopBackgroundCaptureGuard implements BackgroundCaptureGuard {
  const NoopBackgroundCaptureGuard();

  @override
  Future<Result<void>> acquire() async => const Result.ok(null);

  @override
  Future<void> release() async {}

  @override
  Future<bool> isBatteryOptimizationDisabled() async => true;

  @override
  Future<void> requestBatteryOptimizationExemption() async {}
}
