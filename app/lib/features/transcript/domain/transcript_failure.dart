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

/// La taille de lecture n'a pas pu être lue ou écrite. Sans conséquence pour
/// la session en cours — le fil s'ouvre sur la taille par défaut et le réglage
/// reste utilisable, il ne survivra simplement pas à la fermeture de l'app.
final class TranscriptPreferencesFailure extends TranscriptFailure {
  const TranscriptPreferencesFailure(String details)
    : super("Réglage d'affichage non enregistré : $details");
}
