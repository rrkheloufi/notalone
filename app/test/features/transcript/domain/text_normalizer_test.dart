import 'package:flutter_test/flutter_test.dart';
import 'package:notalone/features/transcript/domain/text_normalizer.dart';

void main() {
  group('normalizeForComparison', () {
    test('replie la casse et les accents', () {
      expect(
        normalizeForComparison('Élève À Côté'),
        normalizeForComparison('eleve a cote'),
      );
    });

    test('couvre les accents du français', () {
      expect(
        normalizeForComparison('àâäáãå ç èéêë ìíîï ñ òóôöõ ùúûü ýÿ œ æ'),
        'aaaaaa c eeee iiii n ooooo uuuu yy oe ae',
      );
    });

    test('retire la ponctuation, que les moteurs placent différemment', () {
      // Le même énoncé rendu par deux moteurs : seule la mise en forme change.
      expect(
        normalizeForComparison('Tu peux me passer le sel ?'),
        normalizeForComparison('tu peux me passer le sel'),
      );
    });

    test('compacte les espaces et rogne les bords', () {
      expect(normalizeForComparison('  deux   mots \n'), 'deux mots');
    });

    test('conserve les chiffres, qui portent du sens à table', () {
      expect(normalizeForComparison('à 20 h 30'), 'a 20 h 30');
    });

    test('un texte sans lettre se réduit à du vide', () {
      expect(normalizeForComparison('... !?'), '');
      expect(normalizeForComparison(''), '');
    });
  });
}
