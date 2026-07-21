import 'package:flutter_test/flutter_test.dart';
import 'package:notalone/features/transcript/domain/segment_overlap.dart';

double iou(int aStart, int aEnd, int bStart, int bEnd) => temporalIou(
  aStartMs: aStart,
  aEndMs: aEnd,
  bStartMs: bStart,
  bEndMs: bEnd,
);

void main() {
  group('temporalIou', () {
    test('segments identiques → 1', () {
      expect(iou(1000, 3000, 1000, 3000), 1);
    });

    test('segments disjoints → 0', () {
      expect(iou(1000, 2000, 3000, 4000), 0);
    });

    test('segments qui se touchent sans se recouvrir → 0', () {
      expect(iou(1000, 2000, 2000, 3000), 0);
    });

    test('symétrique', () {
      expect(iou(1000, 3000, 2000, 5000), iou(2000, 5000, 1000, 3000));
    });

    test('recouvrement partiel', () {
      // Intersection 1000 ms, union 4000 ms.
      expect(iou(1000, 3000, 2000, 5000), closeTo(0.25, 0.0001));
    });

    test('un segment contenu dans un autre vaut le rapport des durées', () {
      expect(iou(0, 4000, 1000, 3000), closeTo(0.5, 0.0001));
    });

    test('deux micros sur la même phrase restent bien au-dessus du seuil', () {
      // Bornes VAD décalées de ~200 ms de chaque côté, cas nominal du
      // cross-talk (cf. fixtures).
      expect(iou(10000, 12400, 10180, 12180), greaterThan(0.8));
    });

    test('durée nulle : même instant → 1, instants différents → 0', () {
      expect(iou(1000, 1000, 1000, 1000), 1);
      expect(iou(1000, 1000, 1001, 1001), 0);
    });
  });
}
