import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:notalone/features/capture/domain/speech_segmenter.dart';
import 'package:notalone/features/capture/domain/vad_config.dart';

// Config par défaut : frames de 512 samples = 32 ms à 16 kHz.
// minSpeechMs 200 → confirmation au bout de 7 frames (3584 ≥ 3200 samples).
// minSilenceMs 600 → clôture au bout de 19 frames (9728 ≥ 9600 samples).
const config = VadConfig();
const frameMs = 32;
const speech = 0.9;
const silence = 0.01;

Float32List frameOf(double amplitude) =>
    Float32List(config.frameSize)..fillRange(0, config.frameSize, amplitude);

List<SegmenterEvent> feed(
  SpeechSegmenter segmenter,
  List<(double, double)> frames,
) => [
  for (final (amplitude, probability) in frames)
    ?segmenter.addFrame(frameOf(amplitude), probability),
];

List<(double, double)> repeat(int count, double amplitude, double p) =>
    List.filled(count, (amplitude, p));

void main() {
  late SpeechSegmenter segmenter;

  setUp(() => segmenter = SpeechSegmenter(config: config));

  test('silence seul → aucun événement', () {
    expect(feed(segmenter, repeat(50, 0, silence)), isEmpty);
  });

  test(
    'parole → SpeechStarted rétroactif puis SpeechEnded aux bons instants',
    () {
      final events = feed(segmenter, [
        ...repeat(5, 0, silence),
        ...repeat(7, 0.5, speech),
        ...repeat(19, 0, silence),
      ]);

      expect(events, hasLength(2));
      final started = events[0] as SpeechStarted;
      // Horodaté au début réel de la parole (frame 5), pas à la confirmation.
      expect(started.tStartMs, 5 * frameMs);
      final ended = events[1] as SpeechEnded;
      expect(ended.segment.tStartMs, 5 * frameMs);
      expect(ended.segment.tEndMs, (5 + 7) * frameMs);
      expect(ended.segment.durationMs, 7 * frameMs);
      expect(ended.segment.energyDbfs, closeTo(-6.02, 0.05));
    },
  );

  test('le retard de confirmation reste sous 300 ms (critère MVP-02)', () {
    // 7 frames de 32 ms = 224 ms entre le début de la parole et l'événement.
    final delayMs =
        (config.minSpeechSamples / config.frameSize).ceil() * frameMs;
    expect(delayMs, lessThan(300));
  });

  test('candidat trop court → abandonné sans événement', () {
    final events = feed(segmenter, [
      ...repeat(2, 0, silence),
      ...repeat(3, 0.5, speech),
      ...repeat(30, 0, silence),
    ]);
    expect(events, isEmpty);
  });

  test('micro-pause < minSilenceMs → un seul segment', () {
    final events = feed(segmenter, [
      ...repeat(10, 0.5, speech),
      ...repeat(10, 0, silence), // 320 ms < 600 ms : pause interne
      ...repeat(10, 0.5, speech),
      ...repeat(19, 0, silence),
    ]);

    expect(events, hasLength(2));
    final ended = events[1] as SpeechEnded;
    expect(ended.segment.tStartMs, 0);
    expect(ended.segment.tEndMs, 30 * frameMs);
  });

  test("l'énergie d'une micro-pause interne est intégrée au segment", () {
    final events = feed(segmenter, [
      ...repeat(10, 0.5, speech),
      ...repeat(5, 0, silence),
      ...repeat(10, 0.5, speech),
      ...repeat(19, 0, silence),
    ]);
    // 20 frames à 0,25 de carré moyen + 5 frames muettes → 0,2 → -6,99 dBFS.
    final ended = events[1] as SpeechEnded;
    expect(ended.segment.energyDbfs, closeTo(-6.99, 0.05));
  });

  test('le silence de clôture ne dilue pas l énergie, même bruyant', () {
    final events = feed(segmenter, [
      ...repeat(10, 0.5, speech),
      // Non-parole forte (TV…) : exclue de l'énergie du segment.
      ...repeat(19, 0.3, silence),
    ]);
    final ended = events[1] as SpeechEnded;
    expect(ended.segment.energyDbfs, closeTo(-6.02, 0.05));
  });

  test(
    'hystérésis : pas de clignotement autour du seuil pendant la parole',
    () {
      final oscillating = [
        for (var i = 0; i < 20; i++) (0.5, i.isEven ? 0.45 : 0.40),
      ];
      final events = feed(segmenter, [
        ...repeat(7, 0.5, speech),
        ...oscillating, // sous le seuil haut mais au-dessus du seuil bas
      ]);
      expect(events, hasLength(1));
      expect(events.single, isA<SpeechStarted>());

      final flushed = segmenter.flush()! as SpeechEnded;
      expect(flushed.segment.tEndMs, (7 + 20) * frameMs);
    },
  );

  test('hystérésis : sous le seuil haut, le silence reste du silence', () {
    expect(feed(segmenter, repeat(30, 0.2, 0.45)), isEmpty);
  });

  test(
    "un creux d'attaque au-dessus du seuil bas n'avorte pas le candidat",
    () {
      final events = feed(segmenter, [
        (0.5, 0.6),
        (0.5, 0.4),
        (0.5, 0.4),
        ...repeat(4, 0.5, 0.6),
      ]);
      expect(events.single, isA<SpeechStarted>());
    },
  );

  test('voix forte vs voix faible : ~20 dB d écart d énergie', () {
    final events = feed(segmenter, [
      ...repeat(10, 0.5, speech), // voix à 30 cm
      ...repeat(19, 0, silence),
      ...repeat(10, 0.05, speech), // voix à 1,5 m
      ...repeat(19, 0, silence),
    ]);

    expect(events, hasLength(4));
    final strong = (events[1] as SpeechEnded).segment.energyDbfs;
    final weak = (events[3] as SpeechEnded).segment.energyDbfs;
    expect(strong - weak, closeTo(20, 0.1));
  });

  test('flush en pleine parole → segment clos à la dernière frame parlée', () {
    feed(segmenter, repeat(10, 0.5, speech));
    final ended = segmenter.flush()! as SpeechEnded;
    expect(ended.segment.tStartMs, 0);
    expect(ended.segment.tEndMs, 10 * frameMs);
    expect(ended.segment.energyDbfs, closeTo(-6.02, 0.05));
  });

  test('flush pendant un candidat non confirmé → rien', () {
    feed(segmenter, repeat(3, 0.5, speech));
    expect(segmenter.flush(), isNull);
  });

  test('flush au repos → rien', () {
    expect(segmenter.flush(), isNull);
  });

  test("reset → l'horloge interne repart de zéro", () {
    feed(segmenter, [
      ...repeat(10, 0.5, speech),
      ...repeat(19, 0, silence),
    ]);
    segmenter.reset();

    final events = feed(segmenter, repeat(7, 0.5, speech));
    expect((events.single as SpeechStarted).tStartMs, 0);
  });

  test('une frame vide est ignorée', () {
    expect(segmenter.addFrame(Float32List(0), speech), isNull);
  });

  group('buffer audio', () {
    test('le segment porte le pré-roll puis la parole puis la clôture', () {
      // 10 frames de silence audible (bruit de salle) avant la parole : le
      // pré-roll ne doit en garder que les 200 dernières ms.
      final events = feed(segmenter, [
        ...repeat(10, 0.1, silence),
        ...repeat(10, 0.5, speech),
        ...repeat(19, 0, silence),
      ]);

      final samples = (events[1] as SpeechEnded).segment.samples;
      const preRoll = 3200; // 200 ms à 16 kHz
      expect(preRoll, config.preRollSamples);
      expect(samples, hasLength(preRoll + (10 + 19) * config.frameSize));
      expect(samples.take(preRoll), everyElement(closeTo(0.1, 1e-6)));
      expect(
        samples.skip(preRoll).take(10 * config.frameSize),
        everyElement(closeTo(0.5, 1e-6)),
      );
      expect(samples.skip(preRoll + 10 * config.frameSize), everyElement(0));
    });

    test('un pré-roll plus court que sa fenêtre est pris tel quel', () {
      // Deux frames seulement avant la parole : 1024 samples, pas 3200.
      final events = feed(segmenter, [
        ...repeat(2, 0.1, silence),
        ...repeat(10, 0.5, speech),
        ...repeat(19, 0, silence),
      ]);

      final samples = (events[1] as SpeechEnded).segment.samples;
      expect(samples, hasLength(2 * config.frameSize + 29 * config.frameSize));
      expect(
        samples.take(2 * config.frameSize),
        everyElement(closeTo(0.1, 1e-6)),
      );
    });

    test('un candidat abandonné ne fuit pas dans le segment suivant', () {
      final events = feed(segmenter, [
        ...repeat(3, 0.9, speech), // candidat trop court, abandonné
        ...repeat(30, 0, silence),
        ...repeat(10, 0.5, speech),
        ...repeat(19, 0, silence),
      ]);

      final samples = (events[1] as SpeechEnded).segment.samples;
      expect(
        samples,
        hasLength(config.preRollSamples + 29 * config.frameSize),
      );
      // Le pré-roll ne contient que du silence : la salve à 0,9 est bien plus
      // ancienne que 200 ms et a été chassée du tampon circulaire.
      expect(samples.take(config.preRollSamples), everyElement(0));
    });

    test('pré-roll désactivé → le segment commence à la parole', () {
      final noPreRoll = SpeechSegmenter(config: const VadConfig(preRollMs: 0));
      final events = feed(noPreRoll, [
        ...repeat(10, 0.1, silence),
        ...repeat(10, 0.5, speech),
        ...repeat(19, 0, silence),
      ]);

      final samples = (events[1] as SpeechEnded).segment.samples;
      expect(samples, hasLength(29 * config.frameSize));
      expect(
        samples.take(10 * config.frameSize),
        everyElement(closeTo(0.5, 1e-6)),
      );
    });
  });

  group('découpe forcée', () {
    // 500 ms → coupure toutes les 16 frames au plus (15,625 arrondi).
    const short = VadConfig(maxSegmentMs: 500);

    test('une tirade est coupée en segments qui ne dépassent pas la borne', () {
      final long = SpeechSegmenter(config: short);
      final events = feed(long, repeat(100, 0.5, speech));

      final ended = events.whereType<SpeechEnded>().toList();
      expect(ended, isNotEmpty);
      for (final event in ended) {
        expect(event.segment.durationMs, lessThanOrEqualTo(short.maxSegmentMs));
      }
    });

    test('la parole ne paraît jamais interrompue par une découpe', () {
      final long = SpeechSegmenter(config: short);
      final events = feed(long, repeat(100, 0.5, speech));

      // Un seul début : les découpes suivantes n'en réémettent pas.
      expect(events.whereType<SpeechStarted>(), hasLength(1));
      expect(long.isSpeaking, isTrue);
    });

    test('les segments découpés se suivent sans trou ni recouvrement', () {
      final long = SpeechSegmenter(config: short);
      final events = feed(long, repeat(100, 0.5, speech));
      final ended = events.whereType<SpeechEnded>().toList();

      for (var i = 1; i < ended.length; i++) {
        expect(ended[i].segment.tStartMs, ended[i - 1].segment.tEndMs);
      }
    });

    test('chaque morceau garde son propre audio', () {
      final long = SpeechSegmenter(config: short);
      final events = feed(long, repeat(100, 0.5, speech));
      final ended = events.whereType<SpeechEnded>().toList();

      // Le premier porte le pré-roll, les suivants enchaînent sans (l'audio
      // est continu, il n'y a rien à rattraper).
      expect(ended.first.segment.samples.length, greaterThan(0));
      for (final event in ended.skip(1)) {
        final durationSamples =
            event.segment.durationMs * short.sampleRate ~/ 1000;
        expect(event.segment.samples.length, greaterThanOrEqualTo(
          durationSamples,
        ));
      }
    });

    test('la borne par défaut tient le critère « segments < 15 s »', () {
      final long = SpeechSegmenter(config: config);
      final events = feed(long, repeat(600, 0.5, speech)); // 19,2 s
      final ended = events.whereType<SpeechEnded>().toList();

      expect(ended, isNotEmpty);
      for (final event in ended) {
        expect(event.segment.durationMs, lessThan(15000));
      }
    });
  });
}
