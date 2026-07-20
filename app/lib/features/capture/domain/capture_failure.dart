import 'package:notalone/core/result/failure.dart';

sealed class CaptureFailure extends Failure {
  const CaptureFailure(super.message);
}

final class MicPermissionFailure extends CaptureFailure {
  const MicPermissionFailure() : super('Permission micro refusée');
}

final class MicCaptureFailure extends CaptureFailure {
  const MicCaptureFailure(String details) : super('Capture micro : $details');
}

final class VadInitializationFailure extends CaptureFailure {
  const VadInitializationFailure(String details)
    : super('Initialisation VAD : $details');
}

final class VadInferenceFailure extends CaptureFailure {
  const VadInferenceFailure(String details) : super('Inférence VAD : $details');
}

/// L'OS a refusé ce qui permet de capter écran verrouillé (foreground
/// service Android). Sans cela la capture s'arrêterait au verrouillage.
final class BackgroundCaptureFailure extends CaptureFailure {
  const BackgroundCaptureFailure(String details)
    : super('Capture en arrière-plan : $details');
}
