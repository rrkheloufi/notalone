import 'package:flutter_test/flutter_test.dart';
import 'package:notalone/features/transcript/domain/text_normalizer.dart';
import 'package:notalone/features/transcript/domain/text_similarity.dart';

void main() {
  group('levenshteinDistance', () {
    test('chaînes identiques → 0', () {
      expect(levenshteinDistance('bonjour', 'bonjour'), 0);
    });

    test("chaîne vide → longueur de l'autre", () {
      expect(levenshteinDistance('', 'sel'), 3);
      expect(levenshteinDistance('sel', ''), 3);
      expect(levenshteinDistance('', ''), 0);
    });

    test('substitution, insertion, suppression', () {
      expect(levenshteinDistance('sel', 'sol'), 1);
      expect(levenshteinDistance('sel', 'seul'), 1);
      expect(levenshteinDistance('seul', 'sel'), 1);
    });

    test('symétrique', () {
      expect(
        levenshteinDistance('gratin dauphinois', 'graton dauphinoi'),
        levenshteinDistance('graton dauphinoi', 'gratin dauphinois'),
      );
    });

    test('maxDistance abandonne sans mentir sur la conclusion', () {
      const a = 'tu peux me passer le sel';
      const b = 'je reprendrais bien du gratin';
      final exact = levenshteinDistance(a, b);
      final bounded = levenshteinDistance(a, b, maxDistance: 3);

      expect(exact, greaterThan(3));
      // La valeur rendue n'est pas la distance réelle, mais elle suffit à
      // conclure que le budget est dépassé.
      expect(bounded, 4);
    });

    test('maxDistance non atteint → distance exacte', () {
      expect(levenshteinDistance('sel', 'seul', maxDistance: 3), 1);
    });
  });

  group('normalizedSimilarity', () {
    test('identiques → 1, dont deux vides', () {
      expect(normalizedSimilarity('bonjour', 'bonjour'), 1);
      expect(normalizedSimilarity('', ''), 1);
    });

    test('rien en commun → proche de 0', () {
      expect(normalizedSimilarity('abc', 'xyz'), 0);
      expect(normalizedSimilarity('', 'sel'), 0);
    });

    test('une faute sur une phrase longue reste très similaire', () {
      final a = normalizeForComparison('Tu peux me passer le sel ?');
      final b = normalizeForComparison('tu peux me passer le seul');

      expect(normalizedSimilarity(a, b), greaterThan(0.9));
    });

    test('deux phrases différentes du même repas restent loin du seuil', () {
      final a = normalizeForComparison("Il fait chaud aujourd'hui");
      final b = normalizeForComparison('Je reprendrais bien du gratin');

      expect(normalizedSimilarity(a, b), lessThan(0.5));
    });
  });

  group('isSimilarAtLeast', () {
    test('rend le même verdict que le calcul complet', () {
      const pairs = [
        ('tu peux me passer le sel', 'tu peux me passer le seul'),
        ('il fait chaud aujourd hui', 'je reprendrais bien du gratin'),
        ('oui', 'oui oui'),
        ('bonjour tout le monde', 'bonjour tout le monde'),
        ('', 'quelque chose'),
      ];
      for (final threshold in [0.5, 0.7, 0.9]) {
        for (final (a, b) in pairs) {
          expect(
            isSimilarAtLeast(a, b, threshold),
            normalizedSimilarity(a, b) >= threshold,
            reason: '"$a" vs "$b" au seuil $threshold',
          );
        }
      }
    });

    test('deux chaînes vides sont similaires à tout seuil atteignable', () {
      expect(isSimilarAtLeast('', '', 1), isTrue);
    });

    test('écart de longueur trop grand : refusé sans calcul', () {
      // « oui » ne peut pas être à 0,7 d'une phrase de 40 caractères, quelle
      // que soit la distance : le rapport des longueurs le borne déjà.
      expect(
        isSimilarAtLeast('oui', 'tu peux me passer le sel je te prie', 0.7),
        isFalse,
      );
    });
  });
}
