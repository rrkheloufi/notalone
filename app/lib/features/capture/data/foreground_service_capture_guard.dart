import 'package:flutter/services.dart';
import 'package:notalone/core/result/result.dart';
import 'package:notalone/features/capture/domain/background_capture_guard.dart';
import 'package:notalone/features/capture/domain/capture_failure.dart';

/// Maintien de la capture sur Android : un foreground service de type
/// `microphone`, sans lequel l'OS retire le micro à l'app dès qu'elle passe
/// en arrière-plan (doc 02 §8).
///
/// Service maison (`CaptureForegroundService.kt`) plutôt qu'un package :
/// `flutter_foreground_task`, seul candidat sérieux, n'expose qu'un podspec —
/// sa présence dans le graphe suffisait à réintroduire CocoaPods dans le build
/// iOS, que MVP-02 avait dû quitter pour Swift Package Manager. Un service
/// Android-only ne touche pas iOS, qui n'a de toute façon besoin de rien
/// (voir `NoopBackgroundCaptureGuard`).
class ForegroundServiceCaptureGuard implements BackgroundCaptureGuard {
  ForegroundServiceCaptureGuard({
    required this.notificationTitle,
    required this.notificationText,
  });

  /// Miroir de `MainActivity.CHANNEL`.
  static const MethodChannel channel = MethodChannel(
    'notalone/background_capture',
  );

  final String notificationTitle;
  final String notificationText;

  @override
  Future<Result<void>> acquire() async {
    try {
      await channel.invokeMethod<void>('start', {
        'title': notificationTitle,
        'text': notificationText,
      });
      return const Result.ok(null);
    } on PlatformException catch (exception) {
      return Result.err(
        BackgroundCaptureFailure(exception.message ?? exception.code),
      );
    } on MissingPluginException catch (exception) {
      return Result.err(BackgroundCaptureFailure('$exception'));
    }
  }

  @override
  Future<void> release() async {
    try {
      await channel.invokeMethod<void>('stop');
    } on PlatformException {
      // Arrêt best-effort : le service est abandonné quoi qu'il arrive.
    }
  }

  @override
  Future<bool> isBatteryOptimizationDisabled() async {
    try {
      return await channel.invokeMethod<bool>(
            'isBatteryOptimizationDisabled',
          ) ??
          false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<void> requestBatteryOptimizationExemption() async {
    try {
      await channel.invokeMethod<void>('requestBatteryOptimizationExemption');
    } on PlatformException {
      // L'exemption n'est qu'une assurance : son refus ne bloque rien.
    }
  }
}
