import 'package:flutter_test/flutter_test.dart';
import 'package:notalone/features/transcript/domain/transcript_text_scale.dart';

void main() {
  group('TranscriptTextScale', () {
    test('propose trois tailles, strictement croissantes', () {
      expect(TranscriptTextScale.values, hasLength(3));
      final sizes = TranscriptTextScale.values
          .map((scale) => scale.bodySize)
          .toList();
      expect(sizes, orderedEquals([...sizes]..sort()));
      expect(sizes.toSet(), hasLength(3));
    });

    test('le prénom reste plus petit que la phrase à toutes les tailles', () {
      for (final scale in TranscriptTextScale.values) {
        expect(
          scale.speakerSize,
          lessThan(scale.bodySize),
          reason: 'la phrase est ce qui se lit, pas le prénom ($scale)',
        );
      }
    });

    test('la taille maximale vise la lisibilité à 60 cm', () {
      // Critère MVP-12. ~44 px logiques est le plancher retenu pour une
      // hauteur de capitale d'environ 3 mm à cette distance.
      expect(TranscriptTextScale.maximum.bodySize, greaterThanOrEqualTo(44));
    });

    test('agrandir puis réduire ramène à la taille de départ', () {
      const start = TranscriptTextScale.large;
      expect(start.larger.smaller, start);
    });

    test('les extrémités ne bouclent pas', () {
      expect(
        TranscriptTextScale.values.last.larger,
        TranscriptTextScale.values.last,
      );
      expect(
        TranscriptTextScale.values.first.smaller,
        TranscriptTextScale.values.first,
      );
      expect(TranscriptTextScale.values.last.hasLarger, isFalse);
      expect(TranscriptTextScale.values.first.hasSmaller, isFalse);
    });

    test('relit une taille depuis son nom', () {
      for (final scale in TranscriptTextScale.values) {
        expect(TranscriptTextScale.fromName(scale.name), scale);
      }
    });

    test('un réglage inconnu ou absent retombe sur la taille initiale', () {
      expect(TranscriptTextScale.fromName(null), TranscriptTextScale.initial);
      expect(TranscriptTextScale.fromName(''), TranscriptTextScale.initial);
      expect(
        TranscriptTextScale.fromName('gigantesque'),
        TranscriptTextScale.initial,
      );
      // Un index, comme l'écrirait une version qui aurait stocké l'ordinal :
      // le fil s'ouvre quand même.
      expect(TranscriptTextScale.fromName('1'), TranscriptTextScale.initial);
    });
  });
}
