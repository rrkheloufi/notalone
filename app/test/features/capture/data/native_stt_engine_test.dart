import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notalone/features/capture/data/native_stt_engine.dart';
import 'package:notalone/features/capture/data/stt_error_mapper.dart';
import 'package:notalone/features/capture/domain/speech_segment.dart';
import 'package:notalone/features/capture/domain/stt_failure.dart';

/// Contrairement aux autres platform channels du projet (ONNX, `record`,
/// `permission_handler`), celui-ci est piloté par nous de bout en bout : on
/// peut donc rejouer le contrat natif en CI et vérifier la traduction des
/// codes d'erreur, qui est la partie de MVP-10 la plus facile à casser.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('notalone/stt');
  final calls = <MethodCall>[];

  void mockChannel(Future<Object?>? Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) {
          calls.add(call);
          return handler(call);
        });
  }

  setUp(calls.clear);

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  SpeechSegment segment() => SpeechSegment(
    segmentId: 's1',
    tStartMs: 1000,
    tEndMs: 2000,
    energyDbfs: -14,
    samples: Float32List.fromList([0.1, -0.2, 0.3]),
    sampleRate: 16000,
  );

  group('NativeSttEngine.prepare', () {
    test('adopte les capacités déclarées par le natif', () async {
      mockChannel(
        (_) async => <String, Object?>{
          'engine': 'ios_speech_analyzer',
          'languageTag': 'fr-FR',
          'supportsPartials': true,
          'isOnDevice': true,
          'requiresNetwork': false,
        },
      );
      final engine = NativeSttEngine(channel: channel);

      expect(engine.capabilities.engine, NativeSttEngine.unpreparedEngine);
      expect((await engine.prepare()).isOk, isTrue);

      expect(engine.capabilities.engine, 'ios_speech_analyzer');
      expect(engine.capabilities.supportsPartials, isTrue);
      expect(engine.capabilities.isOnDevice, isTrue);
      expect(calls.single.method, 'prepare');
      expect(
        (calls.single.arguments as Map)['languageTag'],
        'fr-FR',
      );
    });

    test('traduit le modèle absent en Failure explicite', () async {
      mockChannel(
        (_) async => throw PlatformException(
          code: SttErrorCode.modelMissing,
          message: 'modèle fr-FR non installé',
        ),
      );
      final engine = NativeSttEngine(channel: channel);

      final failure = (await engine.prepare()).failureOrNull;

      expect(failure, isA<SttModelMissingFailure>());
      expect((failure! as SttModelMissingFailure).languageTag, 'fr-FR');
    });

    test('traduit le refus d’autorisation iOS', () async {
      mockChannel(
        (_) async =>
            throw PlatformException(code: SttErrorCode.permissionDenied),
      );

      expect(
        (await NativeSttEngine(channel: channel).prepare()).failureOrNull,
        isA<SttPermissionFailure>(),
      );
    });

    test('supporte un natif qui ne déclare rien', () async {
      mockChannel((_) async => null);
      final engine = NativeSttEngine(channel: channel);

      expect((await engine.prepare()).isOk, isTrue);
      expect(engine.capabilities.engine, NativeSttEngine.unpreparedEngine);
      expect(engine.capabilities.languageTag, 'fr-FR');
    });
  });

  group('NativeSttEngine.transcribe', () {
    test('envoie les samples et rend le texte', () async {
      mockChannel(
        (_) async => <String, Object?>{
          'text': 'passe-moi le sel',
          'engine': 'android_on_device',
          'languageTag': 'fr-FR',
        },
      );

      final result = await NativeSttEngine(
        channel: channel,
      ).transcribe(segment());

      final transcription = result.valueOrNull!;
      expect(transcription.text, 'passe-moi le sel');
      expect(transcription.engine, 'android_on_device');
      expect(transcription.isFinal, isTrue);

      final arguments = calls.single.arguments as Map;
      expect(arguments['sampleRate'], 16000);
      expect(arguments['samples'] as Float32List, hasLength(3));
    });

    test('accepte un texte vide sans le prendre pour une panne', () async {
      mockChannel((_) async => <String, Object?>{'text': ''});

      final result = await NativeSttEngine(
        channel: channel,
      ).transcribe(segment());

      expect(result.isOk, isTrue);
      expect(result.valueOrNull!.isEmpty, isTrue);
    });

    test('signale un appareil qui refuse notre audio', () async {
      mockChannel(
        (_) async => throw PlatformException(
          code: SttErrorCode.audioSourceUnsupported,
          message: 'code 3',
        ),
      );

      expect(
        (await NativeSttEngine(
          channel: channel,
        ).transcribe(segment())).failureOrNull,
        isA<SttAudioSourceUnsupportedFailure>(),
      );
    });

    test('traite une réponse nulle comme une panne', () async {
      mockChannel((_) async => null);

      expect(
        (await NativeSttEngine(
          channel: channel,
        ).transcribe(segment())).failureOrNull,
        isA<SttTranscriptionFailure>(),
      );
    });

    test(
      'rend une panne plutôt qu’une exception sans implémentation',
      () async {
        // Aucun handler installé : le canal n'existe pas sur cette plateforme.
        final engine = NativeSttEngine(channel: channel);

        expect(
          (await engine.prepare()).failureOrNull,
          isA<SttUnavailableFailure>(),
        );
        expect(
          (await engine.transcribe(segment())).failureOrNull,
          isA<SttUnavailableFailure>(),
        );
      },
    );
  });

  group('NativeSttEngine.dispose', () {
    test('libère la session native', () async {
      mockChannel((_) async => null);

      await NativeSttEngine(channel: channel).dispose();

      expect(calls.single.method, 'dispose');
    });

    test('ne propage pas l’échec de libération', () async {
      mockChannel((_) async => throw PlatformException(code: 'boom'));

      await expectLater(
        NativeSttEngine(channel: channel).dispose(),
        completes,
      );
    });

    test('ne propage rien sans implémentation native', () async {
      await expectLater(NativeSttEngine(channel: channel).dispose(), completes);
    });
  });
}
