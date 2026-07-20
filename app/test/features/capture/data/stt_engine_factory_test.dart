import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:notalone/features/capture/data/native_stt_engine.dart';
import 'package:notalone/features/capture/data/stt_engine_factory.dart';
import 'package:notalone/features/capture/domain/speech_segment.dart';
import 'package:notalone/features/capture/domain/stt_failure.dart';

void main() {
  SpeechSegment segment() => SpeechSegment(
    segmentId: 's1',
    tStartMs: 0,
    tEndMs: 1000,
    energyDbfs: -14,
    samples: Float32List(16),
    sampleRate: 16000,
  );

  group('createSttEngine', () {
    test('choisit le moteur natif sur mobile, le repli ailleurs', () {
      final engine = createSttEngine();

      // La suite tourne sur le poste de dev : c'est la branche « pas de moteur
      // natif » qui est vérifiable ici. La branche mobile ne l'est que sur
      // appareil (comme les autres platform channels du projet).
      if (Platform.isIOS || Platform.isAndroid) {
        expect(engine, isA<NativeSttEngine>());
      } else {
        expect(engine, isA<UnsupportedSttEngine>());
      }
    });

    test('transmet la langue demandée', () {
      expect(
        createSttEngine(languageTag: 'en-US').capabilities.languageTag,
        'en-US',
      );
    });
  });

  group('UnsupportedSttEngine', () {
    test('échoue franchement plutôt que de rendre du vide', () async {
      final engine = UnsupportedSttEngine();

      expect(
        (await engine.prepare()).failureOrNull,
        isA<SttUnavailableFailure>(),
      );
      expect(
        (await engine.transcribe(segment())).failureOrNull,
        isA<SttUnavailableFailure>(),
      );
    });

    test('se déclare sans moteur et se libère sans rien faire', () async {
      final engine = UnsupportedSttEngine();

      expect(engine.capabilities.engine, 'unsupported');
      await expectLater(engine.dispose(), completes);
    });
  });
}
