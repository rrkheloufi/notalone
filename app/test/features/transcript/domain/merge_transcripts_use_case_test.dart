import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:notalone/features/transcript/domain/dedup_config.dart';
import 'package:notalone/features/transcript/domain/incoming_segment.dart';
import 'package:notalone/features/transcript/domain/merge_transcripts_use_case.dart';
import 'package:notalone/features/transcript/domain/transcript_entry.dart';
import 'package:notalone/features/transcript/domain/transcript_timing_config.dart';

import '../../../fixtures/cross_talk_fixtures.dart';

/// La fenêtre de production, lue sur la config plutôt que recopiée.
final int _windowMs = const TranscriptTimingConfig().reorderWindowMs;

/// Un instant où tout le lot est mûr, sans être si tardif que les entrées
/// sortiraient déjà de la fenêtre aux doublons : les tests qui éprouvent la
/// dédup n'ont pas à jongler avec le réordonnancement, qui a sa propre suite
/// (MVP-09).
int wellAfter(List<IncomingSegment> segments) =>
    segments.map((segment) => segment.tEndMs).reduce((a, b) => a > b ? a : b) +
    _windowMs;

MergeTranscriptsUseCase buildMerge({
  DedupConfig dedup = const DedupConfig(),
  int Function()? now,
  TimerFactory? scheduleAfter,
}) => MergeTranscriptsUseCase(
  dedupConfig: dedup,
  now: now ?? () => 0,
  scheduleAfter: scheduleAfter ?? _neverFires,
);

/// Par défaut les tests pilotent `release` eux-mêmes : le minuteur ne doit pas
/// s'inviter dans le scénario.
Timer _neverFires(Duration duration, void Function() callback) =>
    Timer(const Duration(days: 1), callback);

List<String> textsOf(List<TranscriptEntry> entries) => [
  for (final entry in entries) entry.text,
];

List<String> speakersOf(List<TranscriptEntry> entries) => [
  for (final entry in entries) entry.participantId,
];

void main() {
  group('normalisation temporelle', () {
    test("l'horodatage est ramené sur l'horloge de l'hôte", () {
      final merge = buildMerge();
      addTearDown(merge.dispose);
      // Le téléphone de Marie avance de 2 s sur celui de l'hôte.
      for (var i = 0; i < 5; i++) {
        merge.registerClockProbe(
          participantId: marie,
          hostSentMs: 1000 + i * 10,
          guestReceivedMs: 3010 + i * 10,
          guestSentMs: 3011 + i * 10,
          hostReceivedMs: 1021 + i * 10,
        );
      }
      expect(merge.isSynced(marie), isTrue);

      merge.submit(
        segment(
          participantId: marie,
          segmentId: 's1',
          tStartMs: 12000,
          tEndMs: 14000,
          text: 'Bonjour tout le monde',
          energyDb: dbClose,
        ),
      );
      final released = merge.release(20000);

      expect(released, hasLength(1));
      expect(released.single.tStartMs, closeTo(10000, 50));
      expect(released.single.tEndMs, closeTo(12000, 50));
    });

    test('un invité pas encore synchronisé est daté tel quel, pas perdu', () {
      final merge = buildMerge();
      addTearDown(merge.dispose);

      merge.submit(
        segment(
          participantId: luc,
          segmentId: 's1',
          tStartMs: 5000,
          tEndMs: 6000,
          text: 'Je passe le pain',
          energyDb: dbClose,
        ),
      );
      final released = merge.release(10000);

      expect(merge.isSynced(luc), isFalse);
      expect(released.single.tStartMs, 5000);
    });

    test('deux horloges décalées produisent un fil dans le bon ordre', () {
      final merge = buildMerge();
      addTearDown(merge.dispose);
      // Marie avance de 3 s, Luc retarde de 1 s.
      for (var i = 0; i < 5; i++) {
        merge
          ..registerClockProbe(
            participantId: marie,
            hostSentMs: 1000,
            guestReceivedMs: 4010,
            guestSentMs: 4011,
            hostReceivedMs: 1021,
          )
          ..registerClockProbe(
            participantId: luc,
            hostSentMs: 1000,
            guestReceivedMs: 10,
            guestSentMs: 11,
            hostReceivedMs: 1021,
          );
      }

      // Sur l'horloge hôte : Luc parle à 20 000, Marie répond à 21 000.
      merge
        ..submit(
          segment(
            participantId: marie,
            segmentId: 'marie',
            tStartMs: 24000,
            tEndMs: 24500,
            text: 'Avec plaisir',
            energyDb: dbClose,
          ),
        )
        ..submit(
          segment(
            participantId: luc,
            segmentId: 'luc',
            tStartMs: 19000,
            tEndMs: 19500,
            text: 'Tu veux du gratin',
            energyDb: dbClose,
          ),
        );
      final released = merge.release(40000);

      expect(speakersOf(released), [luc, marie]);
    });
  });

  group('déduplication cross-talk', () {
    test('même phrase, deux micros → une seule entrée, la plus énergique', () {
      final merge = buildMerge();
      addTearDown(merge.dispose);
      final segments = samePhraseTwoMics()..forEach(merge.submit);

      final released = merge.release(wellAfter(segments));

      expect(released, hasLength(1));
      expect(released.single.participantId, papa);
      expect(released.single.text, 'Tu peux me passer le sel ?');
      expect(released.single.mergedSegmentIds, ['marie-echo-sel']);
      expect(merge.deduplicatedSegments, 1);
    });

    test("l'ordre d'arrivée ne change pas le vainqueur", () {
      final merge = buildMerge();
      addTearDown(merge.dispose);
      final segments = samePhraseTwoMics().reversed.toList()
        ..forEach(merge.submit);

      final released = merge.release(wellAfter(segments));

      expect(released, hasLength(1));
      expect(released.single.participantId, papa);
    });

    test('trois micros → une entrée qui porte la trace des deux autres', () {
      final merge = buildMerge();
      addTearDown(merge.dispose);
      final segments = samePhraseThreeMics()..forEach(merge.submit);

      final released = merge.release(wellAfter(segments));

      expect(released, hasLength(1));
      expect(released.single.participantId, papa);
      expect(released.single.duplicateCount, 2);
      expect(
        released.single.mergedSegmentIds,
        containsAll(['marie-echo-sel', 'jeanne-echo-sel']),
      );
    });

    test('trois micros, le plus proche arrivé en dernier', () {
      final merge = buildMerge();
      addTearDown(merge.dispose);
      final segments = samePhraseThreeMics().reversed.toList()
        ..forEach(merge.submit);

      final released = merge.release(wellAfter(segments));

      expect(released, hasLength(1));
      expect(released.single.participantId, papa);
      expect(released.single.duplicateCount, 2);
    });

    test('phrases simultanées mais différentes → deux entrées', () {
      final merge = buildMerge();
      addTearDown(merge.dispose);
      final segments = simultaneousDifferentPhrases()..forEach(merge.submit);

      final released = merge.release(wellAfter(segments));

      expect(released, hasLength(2));
      expect(speakersOf(released), containsAll([marie, luc]));
      expect(merge.deduplicatedSegments, 0);
    });

    test('même texte mais temporellement disjoint → deux entrées', () {
      final merge = buildMerge();
      addTearDown(merge.dispose);
      final segments = samePhraseFarApart()..forEach(merge.submit);

      final released = merge.release(wellAfter(segments));

      expect(released, hasLength(2));
      expect(merge.deduplicatedSegments, 0);
    });

    test("un même locuteur qui se répète n'est jamais dédupliqué", () {
      final merge = buildMerge();
      addTearDown(merge.dispose);
      final segments = sameSpeakerRepeats()..forEach(merge.submit);

      final released = merge.release(wellAfter(segments));

      expect(released, hasLength(2));
      expect(merge.deduplicatedSegments, 0);
    });

    test('chevauchement insuffisant → pas de fusion', () {
      final merge = buildMerge();
      addTearDown(merge.dispose);
      // Textes identiques, mais 200 ms de recouvrement sur 4 s : IoU ≈ 0,05.
      merge
        ..submit(
          segment(
            participantId: papa,
            segmentId: 'a',
            tStartMs: 1000,
            tEndMs: 3000,
            text: 'On mange à quelle heure',
            energyDb: dbClose,
          ),
        )
        ..submit(
          segment(
            participantId: marie,
            segmentId: 'b',
            tStartMs: 2800,
            tEndMs: 4800,
            text: 'On mange à quelle heure',
            energyDb: dbFar,
          ),
        );

      expect(merge.release(10000), hasLength(2));
    });

    test('un segment au texte vide ne fusionne avec personne', () {
      final merge = buildMerge();
      addTearDown(merge.dispose);
      merge
        ..submit(
          segment(
            participantId: papa,
            segmentId: 'a',
            tStartMs: 1000,
            tEndMs: 3000,
            text: '...',
            energyDb: dbClose,
          ),
        )
        ..submit(
          segment(
            participantId: marie,
            segmentId: 'b',
            tStartMs: 1050,
            tEndMs: 3050,
            text: '?!',
            energyDb: dbFar,
          ),
        );

      expect(merge.release(10000), hasLength(2));
      expect(merge.deduplicatedSegments, 0);
    });

    test('les seuils sont pilotés par DedupConfig', () {
      final strict = buildMerge(
        dedup: const DedupConfig(minTextSimilarity: 0.99),
      );
      addTearDown(strict.dispose);
      final segments = samePhraseTwoMics()..forEach(strict.submit);

      // « sel » vs « seul » : 0,96, sous un seuil à 0,99.
      expect(strict.release(wellAfter(segments)), hasLength(2));
    });
  });

  group('doublon tardif', () {
    test('un jumeau arrivé après le figeage est écarté, jamais rétracté', () {
      final merge = buildMerge();
      addTearDown(merge.dispose);
      final segments = samePhraseTwoMics();

      merge.submit(segments.first);
      final first = merge.release(wellAfter(segments));
      expect(first, hasLength(1));

      // Le doublon de Marie arrive une seconde après que la phrase de Papa a
      // été figée.
      merge.submit(segments.last);
      final second = merge.release(wellAfter(segments) + 1000);

      expect(second, isEmpty);
      expect(merge.lateDuplicates, 1);
      expect(merge.deduplicatedSegments, 1);
    });

    test('même plus énergique, le tardif ne remplace pas le figé', () {
      final merge = buildMerge();
      addTearDown(merge.dispose);
      final segments = samePhraseTwoMics();

      // Le micro lointain de Marie arrive et sort le premier…
      merge.submit(segments.last);
      final first = merge.release(wellAfter(segments));
      expect(first.single.participantId, marie);

      // …celui de Papa, pourtant bien plus énergique, arrive trop tard.
      merge.submit(segments.first);
      expect(merge.release(wellAfter(segments) + 500), isEmpty);
      expect(merge.lateDuplicates, 1);
    });

    test('passé la fenêtre aux doublons tardifs, le jumeau ressort', () {
      final merge = buildMerge(
        dedup: const DedupConfig(lateDuplicateWindow: Duration(seconds: 2)),
      );
      addTearDown(merge.dispose);
      final segments = samePhraseTwoMics();

      merge
        ..submit(segments.first)
        ..release(wellAfter(segments))
        // Un tour de fil très postérieur purge l'entrée figée…
        ..release(wellAfter(segments) + 60000)
        ..submit(segments.last);

      expect(merge.release(wellAfter(segments) + 70000), hasLength(1));
      expect(merge.lateDuplicates, 0);
    });
  });

  group('partiels', () {
    test('écartés et comptés, sans jamais atteindre le fil', () {
      final merge = buildMerge();
      addTearDown(merge.dispose);
      merge
        ..submit(
          segment(
            participantId: papa,
            segmentId: 'partiel',
            tStartMs: 1000,
            tEndMs: 2000,
            text: 'Tu peux me passer',
            energyDb: dbClose,
            isFinal: false,
          ),
        )
        ..submit(
          segment(
            participantId: papa,
            segmentId: 'final',
            tStartMs: 1000,
            tEndMs: 2400,
            text: 'Tu peux me passer le sel',
            energyDb: dbClose,
          ),
        );

      final released = merge.release(10000);

      expect(textsOf(released), ['Tu peux me passer le sel']);
      expect(merge.discardedPartials, 1);
      // Le partiel n'a pas non plus compté comme un doublon (doc 02 §5.4).
      expect(merge.deduplicatedSegments, 0);
    });
  });

  group('réordonnancement', () {
    test('une entrée retenue ne sort pas avant sa fenêtre', () {
      final merge = buildMerge();
      addTearDown(merge.dispose);
      merge.submit(
        segment(
          participantId: papa,
          segmentId: 'a',
          tStartMs: 10000,
          tEndMs: 11000,
          text: 'Bonsoir',
          energyDb: dbClose,
        ),
      );

      expect(merge.release(11000), isEmpty);
      expect(merge.pendingEntries, 1);
      expect(merge.release(11500), hasLength(1));
    });

    test('une entrée arrivée après le figeage sort marquée tardive', () {
      final merge = buildMerge();
      addTearDown(merge.dispose);
      merge
        ..submit(
          segment(
            participantId: papa,
            segmentId: 'a',
            tStartMs: 10000,
            tEndMs: 11000,
            text: 'Deuxième',
            energyDb: dbClose,
          ),
        )
        ..release(20000)
        // Segment de Marie prononcé *avant*, arrivé bien après.
        ..submit(
          segment(
            participantId: marie,
            segmentId: 'b',
            tStartMs: 5000,
            tEndMs: 6000,
            text: 'Première',
            energyDb: dbClose,
          ),
        );

      final released = merge.release(21000);

      expect(released.single.text, 'Première');
      expect(released.single.isLate, isTrue);
    });

    test('flush rend ce qui attend sans attendre la fenêtre', () {
      final merge = buildMerge(now: () => 11000);
      addTearDown(merge.dispose);
      merge.submit(
        segment(
          participantId: papa,
          segmentId: 'a',
          tStartMs: 10000,
          tEndMs: 11000,
          text: 'Dernier mot',
          energyDb: dbClose,
        ),
      );

      expect(merge.release(11000), isEmpty);
      expect(textsOf(merge.flush()), ['Dernier mot']);
      expect(merge.pendingEntries, 0);
    });
  });

  group('flux et cycle de vie', () {
    test('les entrées sont publiées sur entries', () async {
      final merge = buildMerge();
      addTearDown(merge.dispose);
      final seen = <TranscriptEntry>[];
      final subscription = merge.entries.listen(seen.add);
      addTearDown(subscription.cancel);

      merge
        ..submit(
          segment(
            participantId: papa,
            segmentId: 'a',
            tStartMs: 1000,
            tEndMs: 2000,
            text: 'Bonjour',
            energyDb: dbClose,
          ),
        )
        ..release(10000);
      await Future<void>.delayed(Duration.zero);

      expect(textsOf(seen), ['Bonjour']);
    });

    test('un réveil est programmé sur la prochaine échéance utile', () {
      final delays = <Duration>[];
      final scheduled = <void Function()>[];
      final merge = buildMerge(
        now: () => 10000,
        scheduleAfter: (duration, callback) {
          delays.add(duration);
          scheduled.add(callback);
          return Timer(const Duration(days: 1), () {});
        },
      );
      addTearDown(merge.dispose);

      merge.submit(
        segment(
          participantId: papa,
          segmentId: 'a',
          tStartMs: 10000,
          tEndMs: 11000,
          text: 'Bonjour',
          energyDb: dbClose,
        ),
      );

      // Fenêtre de 1,5 s à partir du début de la phrase, prise à 10 000.
      expect(delays, [const Duration(milliseconds: 1500)]);

      scheduled.last();
      // Le réveil n'a rien rendu (l'horloge simulée est restée à 10 000) mais
      // il a reprogrammé la prochaine échéance plutôt que de s'arrêter.
      expect(merge.pendingEntries, 1);
      expect(delays, hasLength(2));
    });

    test(
        "forget oublie l'horloge et les entrées figées d'un participant",
        () {
      final merge = buildMerge();
      addTearDown(merge.dispose);
      final segments = samePhraseTwoMics();

      merge
        ..submit(segments.first)
        ..release(wellAfter(segments))
        ..forget(papa)
        // Sans l'entrée figée de Papa, le doublon de Marie n'a plus de jumeau.
        ..submit(segments.last);

      expect(merge.release(wellAfter(segments) + 500), hasLength(1));
      expect(merge.lateDuplicates, 0);
    });

    test("après dispose, plus rien n'entre ni ne sort", () async {
      final merge = buildMerge();
      await merge.dispose();

      merge.submit(
        segment(
          participantId: papa,
          segmentId: 'a',
          tStartMs: 1000,
          tEndMs: 2000,
          text: 'Trop tard',
          energyDb: dbClose,
        ),
      );

      expect(merge.pendingEntries, 0);
      expect(merge.retainedForDedup, 0);
      expect(merge.release(10000), isEmpty);
    });
  });

  group('charge — 8 flux, 2 h de repas', () {
    test('aucun doublon en sortie, aucune phrase perdue, mémoire bornée', () {
      const durationMs = 2 * 60 * 60 * 1000;
      final merge = buildMerge();
      addTearDown(merge.dispose);
      final segments = scriptedMeal(speakers: 8, durationMs: durationMs);
      final utterances = scriptedMealUtterances(durationMs: durationMs);

      final released = <TranscriptEntry>[];
      var maxPending = 0;
      var maxRetained = 0;
      for (final incoming in segments) {
        merge.submit(incoming);
        // Le fil tourne au rythme de l'arrivée des segments : c'est ce que
        // fera le minuteur en production.
        released.addAll(merge.release(incoming.tStartMs + 500));
        maxPending = maxPending > merge.pendingEntries
            ? maxPending
            : merge.pendingEntries;
        maxRetained = maxRetained > merge.retainedForDedup
            ? maxRetained
            : merge.retainedForDedup;
      }
      released.addAll(merge.flush());

      // Chaque énoncé a été capté deux fois et ne sort qu'une.
      expect(segments, hasLength(utterances * 2));
      expect(released, hasLength(utterances));
      expect(merge.deduplicatedSegments, utterances);
      expect(merge.lateDuplicates, 0);

      // Ordre chronologique respecté de bout en bout.
      for (var i = 1; i < released.length; i++) {
        expect(
          released[i].tStartMs,
          greaterThanOrEqualTo(released[i - 1].tStartMs),
        );
      }
      expect(released.every((entry) => !entry.isLate), isTrue);

      // Pas de dérive mémoire : ce que la fusion garde ne dépend pas de la
      // durée du repas mais de ses deux fenêtres.
      expect(maxPending, lessThan(16));
      expect(maxRetained, lessThan(16));
      expect(merge.pendingEntries, 0);
    });

    test('le taux de doublons tient le critère même avec du retard réseau', () {
      const durationMs = 20 * 60 * 1000;
      final merge = buildMerge();
      addTearDown(merge.dispose);
      final segments = scriptedMeal(speakers: 4, durationMs: durationMs);
      final utterances = scriptedMealUtterances(durationMs: durationMs);

      // Un segment sur trois arrive avec 1,2 s de retard : le doublon lointain
      // passe alors *après* que l'original a commencé à attendre.
      final released = <TranscriptEntry>[];
      for (var i = 0; i < segments.length; i++) {
        final lateMs = i % 3 == 0 ? 1200 : 0;
        merge.submit(segments[i]);
        released.addAll(merge.release(segments[i].tStartMs + 500 + lateMs));
      }
      released.addAll(merge.flush());

      final duplicates = released.length - utterances;
      expect(duplicates / utterances, lessThan(0.05));
      // Et surtout : aucune vraie phrase perdue.
      expect(released.length, greaterThanOrEqualTo(utterances));
    });
  });
}
