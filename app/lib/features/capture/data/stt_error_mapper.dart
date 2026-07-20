import 'package:notalone/features/capture/domain/stt_failure.dart';

/// Vocabulaire d'erreurs partagé par les deux implémentations natives
/// (`SttChannel.swift` et `SttChannel.kt`). Les deux OS n'ont ni les mêmes
/// codes ni les mêmes causes de panne : ils les traduisent chacun vers ces
/// codes, de sorte qu'aucun appelant Dart n'ait à savoir sur quel OS il tourne
/// (CLAUDE.md règle 7).
abstract final class SttErrorCode {
  static const String unavailable = 'stt_unavailable';
  static const String modelMissing = 'stt_model_missing';
  static const String permissionDenied = 'stt_permission_denied';
  static const String audioSourceUnsupported = 'stt_audio_source_unsupported';
  static const String failed = 'stt_failed';
  static const String timeout = 'stt_timeout';
}

/// Traduit un code natif en [SttFailure]. Fonction pure et exhaustive :
/// c'est elle qui est testée, le platform channel n'étant pas exécutable en CI.
SttFailure sttFailureFromCode(
  String code, {
  String? details,
  String languageTag = 'fr-FR',
}) {
  final reason = (details == null || details.isEmpty) ? code : details;
  return switch (code) {
    SttErrorCode.unavailable => SttUnavailableFailure(reason),
    SttErrorCode.modelMissing => SttModelMissingFailure(languageTag),
    SttErrorCode.permissionDenied => const SttPermissionFailure(),
    SttErrorCode.audioSourceUnsupported => SttAudioSourceUnsupportedFailure(
      reason,
    ),
    SttErrorCode.timeout => const SttTimeoutFailure(0),
    // Tout code inattendu est une panne de transcription : un moteur qui
    // invente un code ne doit pas faire passer un échec pour un succès.
    _ => SttTranscriptionFailure(reason),
  };
}
