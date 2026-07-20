import 'package:flutter/services.dart';
import 'package:notalone/core/result/result.dart';
import 'package:notalone/features/capture/data/stt_error_mapper.dart';
import 'package:notalone/features/capture/domain/speech_segment.dart';
import 'package:notalone/features/capture/domain/stt_engine.dart';
import 'package:notalone/features/capture/domain/stt_failure.dart';
import 'package:notalone/features/capture/domain/transcription.dart';

/// Le moteur STT on-device des deux OS, derrière un unique platform channel.
///
/// Un seul canal et une seule classe Dart pour iOS et Android : le choix du
/// moteur réel (`SpeechAnalyzer` ≥ iOS 26 ou `SFSpeechRecognizer`,
/// `createOnDeviceSpeechRecognizer` ou le service standard Android) se fait
/// **côté natif**, là où le code est de toute façon spécifique à la
/// plateforme. Côté Dart, seule la fabrique distingue les OS (règle 7), et
/// c'est le natif qui déclare via [capabilities] lequel a été retenu.
class NativeSttEngine implements SttEngine {
  /// [channel] n'est injecté que par les tests, qui rejouent le contrat natif
  /// via `TestDefaultBinaryMessenger`.
  NativeSttEngine({this.languageTag = 'fr-FR', MethodChannel? channel})
    : _channel = channel ?? defaultChannel,
      _capabilities = SttCapabilities(
        engine: unpreparedEngine,
        languageTag: languageTag,
      );

  /// Miroir de `SttChannel.CHANNEL` côté natif.
  static const MethodChannel defaultChannel = MethodChannel('notalone/stt');

  /// Identifiant tant que le natif n'a pas dit quel moteur il a choisi.
  static const String unpreparedEngine = 'native_unprepared';

  final MethodChannel _channel;
  final String languageTag;

  SttCapabilities _capabilities;

  @override
  SttCapabilities get capabilities => _capabilities;

  @override
  Future<Result<void>> prepare() async {
    try {
      final declared = await _channel.invokeMapMethod<String, Object?>(
        'prepare',
        {'languageTag': languageTag},
      );
      _capabilities = _capabilitiesFrom(declared);
      return const Result.ok(null);
    } on PlatformException catch (exception) {
      return Result.err(
        sttFailureFromCode(
          exception.code,
          details: exception.message,
          languageTag: languageTag,
        ),
      );
    } on MissingPluginException catch (exception) {
      // Plateforme sans implémentation native : la fabrique est censée l'avoir
      // écartée, mais un canal absent ne doit jamais remonter en exception.
      return Result.err(SttUnavailableFailure('$exception'));
    }
  }

  @override
  Future<Result<Transcription>> transcribe(SpeechSegment segment) async {
    try {
      final result = await _channel.invokeMapMethod<String, Object?>(
        'transcribe',
        {
          // Le PCM part vers le moteur on-device de l'OS et n'est jamais écrit
          // sur disque des deux côtés du canal (CLAUDE.md règle 2).
          'samples': segment.samples,
          'sampleRate': segment.sampleRate,
          'languageTag': languageTag,
        },
      );
      if (result == null) {
        return const Result.err(
          SttTranscriptionFailure('réponse vide du moteur natif'),
        );
      }
      return Result.ok(
        Transcription(
          text: (result['text'] as String?) ?? '',
          engine: (result['engine'] as String?) ?? _capabilities.engine,
          languageTag: (result['languageTag'] as String?) ?? languageTag,
        ),
      );
    } on PlatformException catch (exception) {
      return Result.err(
        sttFailureFromCode(
          exception.code,
          details: exception.message,
          languageTag: languageTag,
        ),
      );
    } on MissingPluginException catch (exception) {
      return Result.err(SttUnavailableFailure('$exception'));
    }
  }

  @override
  Future<void> dispose() async {
    try {
      await _channel.invokeMethod<void>('dispose');
    } on PlatformException {
      // Libération best-effort : la session native est abandonnée quoi qu'il
      // arrive quand l'app quitte l'écran de capture.
    } on MissingPluginException {
      // Idem : rien à libérer là où il n'y a pas d'implémentation.
    }
  }

  SttCapabilities _capabilitiesFrom(Map<String, Object?>? declared) =>
      SttCapabilities(
        engine: (declared?['engine'] as String?) ?? unpreparedEngine,
        languageTag: (declared?['languageTag'] as String?) ?? languageTag,
        supportsPartials: (declared?['supportsPartials'] as bool?) ?? false,
        isOnDevice: (declared?['isOnDevice'] as bool?) ?? true,
        requiresNetwork: (declared?['requiresNetwork'] as bool?) ?? false,
      );
}
