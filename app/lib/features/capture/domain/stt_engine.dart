import 'package:meta/meta.dart';
import 'package:notalone/core/result/result.dart';
import 'package:notalone/features/capture/domain/speech_segment.dart';
import 'package:notalone/features/capture/domain/transcription.dart';

/// Ce qu'un moteur sait faire. Le reste du code s'y réfère plutôt que de
/// deviner d'après [SttCapabilities.engine] : c'est ce qui permet d'ajouter le
/// moteur cloud (MVP-14) sans toucher aux appelants.
@immutable
class SttCapabilities {
  const SttCapabilities({
    required this.engine,
    required this.languageTag,
    this.supportsPartials = false,
    this.isOnDevice = true,
    this.requiresNetwork = false,
  });

  final String engine;

  final String languageTag;

  /// Aucun moteur MVP-10 n'en émet (décision du 20/07/2026) ; Gladia le fera.
  final bool supportsPartials;

  /// Faux pour le cloud : les réglages (MVP-13) doivent pouvoir prévenir
  /// l'invité que son audio quitterait l'appareil.
  final bool isOnDevice;

  final bool requiresNetwork;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SttCapabilities &&
          other.engine == engine &&
          other.languageTag == languageTag &&
          other.supportsPartials == supportsPartials &&
          other.isOnDevice == isOnDevice &&
          other.requiresNetwork == requiresNetwork);

  @override
  int get hashCode => Object.hash(
    engine,
    languageTag,
    supportsPartials,
    isOnDevice,
    requiresNetwork,
  );
}

/// Frontière vers la reconnaissance vocale (conventions.md §5). Les quatre
/// moteurs du doc 02 §3 — `SpeechAnalyzer`, `SFSpeechRecognizer`, le
/// recognizer on-device Android et Gladia — passent tous par ici, et le reste
/// du code ignore lequel tourne.
abstract interface class SttEngine {
  /// Ce que le moteur a annoncé, connu une fois [prepare] passé. Avant, c'est
  /// une déclaration d'intention (langue et identifiant attendus).
  SttCapabilities get capabilities;

  /// Vérifie la disponibilité du moteur et du modèle français, demande les
  /// autorisations nécessaires et déclenche le téléchargement du modèle quand
  /// l'OS le permet. À appeler avant la première transcription — c'est là que
  /// se décident les `Failure` explicites que l'écran de capture affiche.
  Future<Result<void>> prepare();

  /// Transcrit un segment déjà capté. L'audio est fourni par l'appelant : le
  /// moteur ne prend jamais le micro lui-même (doc 02 §2).
  Future<Result<Transcription>> transcribe(SpeechSegment segment);

  Future<void> dispose();
}
