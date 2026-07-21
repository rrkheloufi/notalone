import 'package:flutter_test/flutter_test.dart';
import 'package:notalone/features/transcript/domain/speaker.dart';

void main() {
  group('Speaker', () {
    test('deux locuteurs identiques sont égaux', () {
      const a = Speaker(id: 'p1', name: 'Papa', colorIndex: 2);
      const b = Speaker(id: 'p1', name: 'Papa', colorIndex: 2);

      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('un renommage donne un locuteur différent', () {
      const before = Speaker(id: 'p1', name: 'Papa', colorIndex: 2);
      const after = Speaker(id: 'p1', name: 'Papou', colorIndex: 2);

      // C'est cette différence qui déclenche la remise à jour des bulles déjà
      // affichées dans le ViewModel.
      expect(before, isNot(after));
    });

    test('même prénom, convives différents : deux locuteurs distincts', () {
      const one = Speaker(id: 'p1', name: 'Camille', colorIndex: 0);
      const other = Speaker(id: 'p2', name: 'Camille', colorIndex: 1);

      expect(one, isNot(other));
    });

    test('se décrit lisiblement', () {
      const speaker = Speaker(id: 'p1', name: 'Papa', colorIndex: 2);

      expect(speaker.toString(), contains('Papa'));
      expect(speaker.toString(), contains('p1'));
    });
  });
}
