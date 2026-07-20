import 'dart:io';

import 'package:notalone/core/result/result.dart';
import 'package:notalone/features/capture/data/native_stt_engine.dart';
import 'package:notalone/features/capture/domain/speech_segment.dart';
import 'package:notalone/features/capture/domain/stt_engine.dart';
import 'package:notalone/features/capture/domain/stt_failure.dart';
import 'package:notalone/features/capture/domain/transcription.dart';

/// **Seul endroit du projet qui distingue les plateformes pour le STT**
/// (CLAUDE.md règle 7, doc 02 §3). Le choix entre les quatre moteurs de la
/// matrice s'y ramène à deux cas côté Dart : les deux OS mobiles partagent le
/// même canal — c'est le natif qui y arbitre `SpeechAnalyzer` contre
/// `SFSpeechRecognizer` et le recognizer on-device contre le service standard,
/// puisqu'il est le seul à connaître la version d'OS réelle.
///
/// Le moteur cloud (MVP-14) se choisira ici aussi, sur le réglage de l'invité.
SttEngine createSttEngine({String languageTag = 'fr-FR'}) =>
    Platform.isIOS || Platform.isAndroid
    ? NativeSttEngine(languageTag: languageTag)
    : UnsupportedSttEngine(languageTag: languageTag);

/// Moteur des plateformes sans STT natif (poste de dev, tests d'intégration).
/// Il échoue franchement plutôt que de rendre du texte vide : un transcript
/// silencieusement muet serait le pire des comportements pour un lecteur sourd.
class UnsupportedSttEngine implements SttEngine {
  UnsupportedSttEngine({String languageTag = 'fr-FR'})
    : capabilities = SttCapabilities(
        engine: 'unsupported',
        languageTag: languageTag,
      );

  @override
  final SttCapabilities capabilities;

  static const SttUnavailableFailure _failure = SttUnavailableFailure(
    'plateforme sans moteur de reconnaissance vocale',
  );

  @override
  Future<Result<void>> prepare() async => const Result.err(_failure);

  @override
  Future<Result<Transcription>> transcribe(SpeechSegment segment) async =>
      const Result.err(_failure);

  @override
  Future<void> dispose() async {}
}
