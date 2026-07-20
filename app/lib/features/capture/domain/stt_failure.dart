import 'package:notalone/core/result/failure.dart';

/// Pannes des moteurs de reconnaissance vocale. Elles sont distinguées parce
/// que l'invité n'a pas le même recours selon les cas : télécharger un modèle,
/// accorder une autorisation, ou basculer sur le moteur cloud (MVP-14).
sealed class SttFailure extends Failure {
  const SttFailure(super.message);
}

/// Aucun moteur natif utilisable sur cet appareil (OS trop ancien, service de
/// reconnaissance absent, plateforme non mobile).
final class SttUnavailableFailure extends SttFailure {
  const SttUnavailableFailure(String details)
    : super('Reconnaissance vocale indisponible : $details');
}

/// Le moteur existe mais le modèle français n'est pas installé. Sur Android on
/// en déclenche le téléchargement ; sur iOS < 26 il faut passer par Réglages,
/// aucune API ne permet de le faire à la place de l'utilisateur.
final class SttModelMissingFailure extends SttFailure {
  const SttModelMissingFailure(this.languageTag)
    : super('Modèle de reconnaissance $languageTag absent');

  final String languageTag;
}

/// iOS < 26 : `SFSpeechRecognizer` réclame une autorisation explicite, même
/// pour de la reconnaissance 100 % on-device.
final class SttPermissionFailure extends SttFailure {
  const SttPermissionFailure()
    : super('Autorisation de reconnaissance vocale refusée');
}

/// Le moteur natif refuse qu'on lui pousse notre propre audio. Sans cela il
/// prendrait le micro lui-même, ce que le pipeline maison exclut (doc 02 §2) :
/// on préfère une panne franche à un moteur qui court-circuite VAD,
/// horodatage et énergie.
final class SttAudioSourceUnsupportedFailure extends SttFailure {
  const SttAudioSourceUnsupportedFailure(String details)
    : super("Ce téléphone n'accepte pas l'audio fourni par l'app : $details");
}

/// Le moteur a échoué sur ce segment précis : le suivant peut réussir.
final class SttTranscriptionFailure extends SttFailure {
  const SttTranscriptionFailure(String details)
    : super('Transcription : $details');
}

/// Le moteur n'a pas rendu de résultat dans le délai imparti. Un segment
/// bloqué ne doit jamais retenir la file : le fil du lecteur avance.
final class SttTimeoutFailure extends SttFailure {
  const SttTimeoutFailure(this.elapsedMs)
    : super('Transcription abandonnée après $elapsedMs ms');

  final int elapsedMs;
}
