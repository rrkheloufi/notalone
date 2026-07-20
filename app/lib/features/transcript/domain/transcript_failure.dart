import 'package:notalone/core/result/failure.dart';

sealed class TranscriptFailure extends Failure {
  const TranscriptFailure(super.message);
}

/// Aller-retour `clock_sync` inexploitable : horodatages non monotones (un
/// t3 avant t0, ou un invité qui répond avant d'avoir reçu). Physiquement
/// impossible, donc soit une horloge qui a sauté pendant l'échange, soit un
/// émetteur fautif — dans les deux cas la mesure est écartée plutôt que
/// d'empoisonner la médiane.
final class ClockProbeInvalidFailure extends TranscriptFailure {
  const ClockProbeInvalidFailure(String details)
    : super("Sonde d'horloge invalide : $details");
}
