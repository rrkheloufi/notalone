import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:notalone/features/capture/domain/speech_segment.dart';
import 'package:notalone/features/capture/domain/stt_engine.dart';
import 'package:notalone/features/capture/domain/transcribed_segment.dart';
import 'package:notalone/features/capture/domain/transcription.dart';

SpeechSegment segment(String id, {int startMs = 1000, double energy = -14}) =>
    SpeechSegment(
      segmentId: id,
      tStartMs: startMs,
      tEndMs: startMs + 1000,
      energyDbfs: energy,
      samples: Float32List(16),
      sampleRate: 16000,
    );

void main() {
  group('Transcription', () {
    test('égalité par valeur sur chaque champ', () {
      const reference = Transcription(text: 'bonjour', engine: 'fake');

      expect(reference, const Transcription(text: 'bonjour', engine: 'fake'));
      expect(
        reference.hashCode,
        const Transcription(text: 'bonjour', engine: 'fake').hashCode,
      );
      expect(
        reference,
        isNot(const Transcription(text: 'bonsoir', engine: 'fake')),
      );
      expect(
        reference,
        isNot(const Transcription(text: 'bonjour', engine: 'gladia')),
      );
      expect(
        reference,
        isNot(
          const Transcription(text: 'bonjour', engine: 'fake', isFinal: false),
        ),
      );
      expect(
        reference,
        isNot(
          const Transcription(
            text: 'bonjour',
            engine: 'fake',
            languageTag: 'en-US',
          ),
        ),
      );
    });

    test('tient un texte vide ou blanc pour vide', () {
      expect(const Transcription(text: '', engine: 'x').isEmpty, isTrue);
      expect(const Transcription(text: '  \n ', engine: 'x').isEmpty, isTrue);
      expect(const Transcription(text: 'a', engine: 'x').isEmpty, isFalse);
    });

    test('est finale et française par défaut', () {
      const transcription = Transcription(text: 'oui', engine: 'x');

      expect(transcription.isFinal, isTrue);
      expect(transcription.languageTag, 'fr-FR');
    });

    test('se décrit lisiblement', () {
      expect(
        const Transcription(text: 'oui', engine: 'fake').toString(),
        'Transcription(fake, "oui")',
      );
    });
  });

  group('TranscribedSegment', () {
    const transcription = Transcription(text: 'bonjour', engine: 'fake');

    TranscribedSegment build({
      String id = 's1',
      int startMs = 1000,
      double energy = -14,
    }) => TranscribedSegment.of(
      segment(id, startMs: startMs, energy: energy),
      transcription,
    );

    test('reprend les métadonnées du segment sans son audio', () {
      final transcribed = build();

      expect(transcribed.segmentId, 's1');
      expect(transcribed.tStartMs, 1000);
      expect(transcribed.tEndMs, 2000);
      expect(transcribed.energyDbfs, -14);
      expect(transcribed.durationMs, 1000);
      expect(transcribed.text, 'bonjour');
      // Rien ne permet de remonter au PCM : le buffer meurt avec le segment.
      expect(transcribed, isNot(isA<SpeechSegment>()));
    });

    test('égalité par valeur sur chaque champ', () {
      expect(build(), build());
      expect(build().hashCode, build().hashCode);
      expect(build(), isNot(build(id: 's2')));
      expect(build(), isNot(build(startMs: 2000)));
      expect(build(), isNot(build(energy: -30)));
      expect(
        build(),
        isNot(
          TranscribedSegment.of(
            segment('s1'),
            const Transcription(text: 'autre', engine: 'fake'),
          ),
        ),
      );
    });
  });

  group('SttCapabilities', () {
    test('égalité par valeur sur chaque champ', () {
      const reference = SttCapabilities(engine: 'fake', languageTag: 'fr-FR');

      expect(
        reference,
        const SttCapabilities(engine: 'fake', languageTag: 'fr-FR'),
      );
      expect(
        reference.hashCode,
        const SttCapabilities(engine: 'fake', languageTag: 'fr-FR').hashCode,
      );
      expect(
        reference,
        isNot(const SttCapabilities(engine: 'gladia', languageTag: 'fr-FR')),
      );
      expect(
        reference,
        isNot(const SttCapabilities(engine: 'fake', languageTag: 'en-US')),
      );
      expect(
        reference,
        isNot(
          const SttCapabilities(
            engine: 'fake',
            languageTag: 'fr-FR',
            supportsPartials: true,
          ),
        ),
      );
      expect(
        reference,
        isNot(
          const SttCapabilities(
            engine: 'fake',
            languageTag: 'fr-FR',
            isOnDevice: false,
          ),
        ),
      );
      expect(
        reference,
        isNot(
          const SttCapabilities(
            engine: 'fake',
            languageTag: 'fr-FR',
            requiresNetwork: true,
          ),
        ),
      );
    });

    test('un moteur est on-device et hors-ligne par défaut', () {
      const capabilities = SttCapabilities(
        engine: 'fake',
        languageTag: 'fr-FR',
      );

      expect(capabilities.isOnDevice, isTrue);
      expect(capabilities.requiresNetwork, isFalse);
      expect(capabilities.supportsPartials, isFalse);
    });
  });
}
