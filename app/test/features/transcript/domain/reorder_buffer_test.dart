import 'package:flutter_test/flutter_test.dart';
import 'package:meta/meta.dart';
import 'package:notalone/features/transcript/domain/reorder_buffer.dart';
import 'package:notalone/features/transcript/domain/transcript_timing_config.dart';

/// Ce que MVP-11 y mettra est une `TranscriptEntry` ; le buffer ne connaît
/// que l'horodatage qu'on lui apprend à lire.
typedef Entry = ({String text, int tMs});

ReorderBuffer<Entry> buildBuffer({int windowMs = 1500}) => ReorderBuffer(
  timestampOf: (entry) => entry.tMs,
  config: TranscriptTimingConfig(
    reorderWindow: Duration(milliseconds: windowMs),
  ),
);

List<String> textsOf(List<ReorderedEntry<Entry>> released) => [
  for (final entry in released) entry.value.text,
];

void main() {
  group('ReorderedEntry', () {
    test('égalité structurelle', () {
      const entry = ReorderedEntry(
        value: (text: 'bonjour', tMs: 1000),
        isLate: false,
      );

      expect(
        entry,
        const ReorderedEntry(
          value: (text: 'bonjour', tMs: 1000),
          isLate: false,
        ),
      );
      expect(
        entry.hashCode,
        const ReorderedEntry(
          value: (text: 'bonjour', tMs: 1000),
          isLate: false,
        ).hashCode,
      );
      expect(
        entry,
        isNot(
          const ReorderedEntry(
            value: (text: 'bonsoir', tMs: 1000),
            isLate: false,
          ),
        ),
      );
      // Le drapeau fait partie de l'identité : la même phrase à l'heure ou
      // en retard ne s'affichera pas pareil (MVP-12).
      expect(
        entry,
        isNot(
          const ReorderedEntry(
            value: (text: 'bonjour', tMs: 1000),
            isLate: true,
          ),
        ),
      );
      expect(entry, isNot(42));
    });
  });

  group('ReorderBuffer — fenêtre', () {
    test('rien ne sort avant la fin de la fenêtre', () {
      final buffer = buildBuffer()..add((text: 'bonjour', tMs: 1000));

      expect(buffer.release(1499), isEmpty);
      expect(buffer.release(2499), isEmpty);
      expect(buffer.pending, 1);

      expect(textsOf(buffer.release(2500)), ['bonjour']);
      expect(buffer.isEmpty, isTrue);
    });

    test('la fenêtre est configurable', () {
      final buffer = buildBuffer(windowMs: 300)
        ..add((text: 'bonjour', tMs: 1000));

      expect(buffer.release(1299), isEmpty);
      expect(textsOf(buffer.release(1300)), ['bonjour']);
    });

    test("une entrée déjà mûre à l'arrivée sort au premier release", () {
      final buffer = buildBuffer()..add((text: 'seule au monde', tMs: 1000));

      final released = buffer.release(9000);

      expect(textsOf(released), ['seule au monde']);
      // Rien n'était figé : elle n'a pas raté sa place.
      expect(released.single.isLate, isFalse);
    });
  });

  group('ReorderBuffer — ordre', () {
    test("des arrivées désordonnées sortent dans l'ordre temporel", () {
      final buffer = buildBuffer()
        ..add((text: 'troisième', tMs: 1200))
        ..add((text: 'première', tMs: 1000))
        ..add((text: 'quatrième', tMs: 1300))
        ..add((text: 'deuxième', tMs: 1100));

      final released = buffer.release(2800);

      expect(textsOf(released), [
        'première',
        'deuxième',
        'troisième',
        'quatrième',
      ]);
      expect(released.every((entry) => !entry.isLate), isTrue);
    });

    test('le réordonnancement rattrape des latences STT différentes', () {
      // Marie parle en premier mais son téléphone transcrit lentement :
      // son segment arrive après celui de Paul.
      final buffer = buildBuffer()
        ..add((text: 'Paul répond', tMs: 5400))
        ..add((text: 'Marie demande', tMs: 5000));

      expect(textsOf(buffer.release(6900)), ['Marie demande', 'Paul répond']);
    });

    test("horodatages égaux : l'ordre d'arrivée départage", () {
      final buffer = buildBuffer()
        ..add((text: 'arrivée en premier', tMs: 1000))
        ..add((text: 'arrivée ensuite', tMs: 1000));

      expect(textsOf(buffer.release(2500)), [
        'arrivée en premier',
        'arrivée ensuite',
      ]);
    });

    test('libération par lots successifs', () {
      final buffer = buildBuffer()
        ..add((text: 'a', tMs: 1000))
        ..add((text: 'b', tMs: 2000));

      expect(textsOf(buffer.release(2500)), ['a']);
      expect(buffer.pending, 1);
      expect(textsOf(buffer.release(3500)), ['b']);
      expect(buffer.isEmpty, isTrue);
    });
  });

  group('ReorderBuffer — entrées tardives', () {
    test(
      'une entrée arrivée après la fenêtre est marquée tardive et ne '
      'réordonne pas ce qui est figé',
      () {
        final buffer = buildBuffer()
          ..add((text: 'figée', tMs: 2000))
          ..add((text: 'figée aussi', tMs: 2200));
        expect(textsOf(buffer.release(3700)), ['figée', 'figée aussi']);

        // Arrive alors que du texte plus récent est déjà sous les yeux du
        // lecteur : sa place chronologique est perdue.
        buffer.add((text: 'en retard', tMs: 2100));
        final released = buffer.release(3800);

        expect(textsOf(released), ['en retard']);
        expect(released.single.isLate, isTrue);
      },
    );

    test("la tardive sort en tête du lot, devant les entrées à l'heure", () {
      final buffer = buildBuffer()
        ..add((text: 'figée', tMs: 2000))
        ..release(3500)
        ..add((text: 'en retard', tMs: 1800))
        ..add((text: "à l'heure", tMs: 2400));

      final released = buffer.release(3900);

      // Chronologiquement la tardive précède l'autre : la mettre en tête
      // reste le placement le plus juste, sans toucher au figé.
      expect(textsOf(released), ['en retard', "à l'heure"]);
      expect(released.first.isLate, isTrue);
      expect(released.last.isLate, isFalse);
    });

    test('une tardive sort sans attendre sa fenêtre', () {
      final buffer = buildBuffer()
        ..add((text: 'figée', tMs: 5000))
        ..release(6500)
        ..add((text: 'en retard', tMs: 4900));

      expect(textsOf(buffer.release(6501)), ['en retard']);
    });

    test('une tardive ne fait pas avancer la ligne de gel', () {
      final buffer = buildBuffer()
        ..add((text: 'figée', tMs: 2000))
        ..release(3500)
        ..add((text: 'très en retard', tMs: 500));

      expect(buffer.release(3600).single.isLate, isTrue);

      // 1800 reste antérieur au dernier figé (2000), donc tardif — la sortie
      // de la précédente n'a pas ramené la ligne de gel à 500.
      buffer.add((text: 'en retard aussi', tMs: 1800));
      expect(buffer.release(3700).single.isLate, isTrue);
    });

    test("un horodatage égal au dernier figé n'est pas tardif", () {
      final buffer = buildBuffer()
        ..add((text: 'figée', tMs: 2000))
        ..release(3500)
        ..add((text: 'même instant', tMs: 2000));

      final released = buffer.release(3600);

      expect(textsOf(released), ['même instant']);
      expect(released.single.isLate, isFalse);
    });

    test("tant que rien n'est sorti, rien ne peut être tardif", () {
      final buffer = buildBuffer()
        ..add((text: 'très ancienne', tMs: 10))
        ..add((text: 'récente', tMs: 5000));

      final released = buffer.release(6500);

      expect(textsOf(released), ['très ancienne', 'récente']);
      expect(released.every((entry) => !entry.isLate), isTrue);
    });
  });

  group('ReorderBuffer — flush et état', () {
    test("flush rend tout, dans l'ordre, sans attendre", () {
      final buffer = buildBuffer()
        ..add((text: 'b', tMs: 2000))
        ..add((text: 'a', tMs: 1000))
        ..add((text: 'c', tMs: 3000));

      expect(textsOf(buffer.flush()), ['a', 'b', 'c']);
      expect(buffer.isEmpty, isTrue);
      expect(buffer.flush(), isEmpty);
    });

    test('flush sort aussi les tardives, marquées', () {
      final buffer = buildBuffer()
        ..add((text: 'figée', tMs: 2000))
        ..release(3500)
        ..add((text: 'en retard', tMs: 1500))
        ..add((text: 'pas encore mûre', tMs: 3000));

      final released = buffer.flush();

      expect(textsOf(released), ['en retard', 'pas encore mûre']);
      expect(released.first.isLate, isTrue);
      expect(released.last.isLate, isFalse);
    });

    test('pending et isEmpty suivent le contenu', () {
      final buffer = buildBuffer();
      expect(buffer.isEmpty, isTrue);
      expect(buffer.pending, 0);

      buffer
        ..add((text: 'a', tMs: 1000))
        ..add((text: 'b', tMs: 1100));
      expect(buffer.pending, 2);
      expect(buffer.isEmpty, isFalse);

      buffer.release(2600);
      expect(buffer.isEmpty, isTrue);
    });

    test('nextDueMs annonce le prochain réveil utile', () {
      final buffer = buildBuffer();
      expect(buffer.nextDueMs, isNull);

      buffer
        ..add((text: 'b', tMs: 2000))
        ..add((text: 'a', tMs: 1000));
      expect(buffer.nextDueMs, 2500); // la plus ancienne + 1,5 s

      buffer.release(2500);
      expect(buffer.nextDueMs, 3500);
    });

    test("nextDueMs d'une tardive est déjà passé : à afficher maintenant", () {
      final buffer = buildBuffer()
        ..add((text: 'figée', tMs: 5000))
        ..release(6500)
        ..add((text: 'en retard', tMs: 4000));

      expect(buffer.nextDueMs, 4000);
      expect(buffer.nextDueMs, lessThan(6500));
    });
  });

  group('ReorderBuffer — arbitrage avant figeage (MVP-11)', () {
    test('pendingEntries expose ce qui attend, tardives comprises', () {
      final buffer = buildBuffer()
        ..add((text: 'première', tMs: 1000))
        ..add((text: 'seconde', tMs: 2000));
      expect(
        buffer.pendingEntries.map((entry) => entry.text),
        containsAll(['première', 'seconde']),
      );

      buffer.release(3500);
      expect(buffer.pendingEntries, isEmpty);

      // Une tardive attend elle aussi son tour : la dédup doit pouvoir
      // l'arbitrer avant qu'elle ne sorte.
      buffer.add((text: 'tardive', tMs: 500));
      expect(
        buffer.pendingEntries.map((entry) => entry.text),
        ['tardive'],
      );
    });

    test('remove retire une entrée encore en attente', () {
      const loser = (text: 'perdante', tMs: 1000);
      final buffer = buildBuffer()
        ..add(loser)
        ..add((text: 'gagnante', tMs: 1050));

      expect(buffer.remove(loser), isTrue);
      expect(buffer.pending, 1);
      expect(textsOf(buffer.release(3000)), ['gagnante']);
    });

    test('remove retire aussi une tardive', () {
      const late = (text: 'tardive', tMs: 1000);
      final buffer = buildBuffer()
        ..add((text: 'figée', tMs: 5000))
        ..release(7000)
        ..add(late);

      expect(buffer.remove(late), isTrue);
      expect(buffer.release(9000), isEmpty);
    });

    test('remove sur une entrée déjà figée ou inconnue rend false', () {
      const frozen = (text: 'figée', tMs: 1000);
      final buffer = buildBuffer()
        ..add(frozen)
        ..release(3000);

      expect(buffer.remove(frozen), isFalse);
      expect(buffer.remove((text: 'jamais vue', tMs: 42)), isFalse);
    });

    test('remove compare par identité, pas par égalité', () {
      // Deux convives peuvent produire deux entrées égales (même texte, même
      // horodatage) : en retirer une ne doit pas emporter l'autre. C'est ce
      // que fait la dédup quand elle écarte une captation sur deux.
      final buffer = ReorderBuffer<_Utterance>(
        timestampOf: (entry) => entry.tMs,
      );
      final first = _utterance('oui', 1000);
      final second = _utterance('oui', 1000);
      buffer
        ..add(first)
        ..add(second);
      expect(first, second, reason: 'les deux entrées sont bien égales');

      expect(buffer.remove(first), isTrue);
      expect(buffer.pending, 1);
      expect(buffer.pendingEntries.single, same(second));
    });

    test('retirer la dernière entrée remet nextDueMs à null', () {
      const only = (text: 'seule', tMs: 1000);
      final buffer = buildBuffer()..add(only);
      expect(buffer.nextDueMs, isNotNull);

      expect(buffer.remove(only), isTrue);
      expect(buffer.nextDueMs, isNull);
      expect(buffer.isEmpty, isTrue);
    });
  });

  group('ReorderBuffer — charge', () {
    test('8 flux entremêlés sur 2 h simulées sortent en ordre et ne '
        'laissent rien derrière', () {
      final buffer = buildBuffer();
      const participants = 8;
      const segmentsPerParticipant = 900; // ~2 h à un segment / 8 s

      var released = 0;
      var late = 0;
      var lastReleasedMs = -1;
      for (var i = 0; i < segmentsPerParticipant; i++) {
        for (var p = 0; p < participants; p++) {
          // Chacun parle à son rythme, avec une latence propre : les
          // horodatages arrivent entremêlés, jamais triés.
          buffer.add((text: 'p$p-$i', tMs: i * 8000 + p * 130));
        }
        for (final entry in buffer.release(i * 8000 + 2000)) {
          released++;
          if (entry.isLate) {
            late++;
          } else {
            expect(entry.value.tMs, greaterThanOrEqualTo(lastReleasedMs));
            lastReleasedMs = entry.value.tMs;
          }
        }
        // Le buffer ne retient jamais plus que la fenêtre : pas de fuite.
        expect(buffer.pending, lessThanOrEqualTo(participants * 2));
      }
      released += buffer.flush().length;

      expect(released, participants * segmentsPerParticipant);
      expect(late, 0);
      expect(buffer.isEmpty, isTrue);
    });
  });
}

/// Fabrique deux à deux distinctes : `const _Utterance(...)` serait
/// canonicalisé, et le test ne prouverait plus rien.
_Utterance _utterance(String text, int tMs) => _Utterance(text, tMs);

/// Deux prises de parole égales mais distinctes : ce que la dédup manipule.
@immutable
class _Utterance {
  const _Utterance(this.text, this.tMs);

  final String text;
  final int tMs;

  @override
  bool operator ==(Object other) =>
      other is _Utterance && other.text == text && other.tMs == tMs;

  @override
  int get hashCode => Object.hash(text, tMs);
}
