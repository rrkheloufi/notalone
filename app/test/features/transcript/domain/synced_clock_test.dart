import 'package:flutter_test/flutter_test.dart';
import 'package:notalone/core/result/result.dart';
import 'package:notalone/features/transcript/domain/clock_probe.dart';
import 'package:notalone/features/transcript/domain/synced_clock.dart';
import 'package:notalone/features/transcript/domain/transcript_failure.dart';
import 'package:notalone/features/transcript/domain/transcript_timing_config.dart';

/// Rejoue un aller-retour `clock_sync` réel : l'horloge de l'invité avance de
/// [offsetMs] sur celle de l'hôte, le message met [upMs] à l'aller, l'invité
/// met [processingMs] à répondre et la réponse met [downMs] au retour.
/// L'erreur théorique de la mesure vaut `(upMs − downMs) / 2` — c'est
/// l'asymétrie du réseau, pas l'offset, qui limite la précision.
Result<ClockOffset> sendProbe(
  SyncedClock clock, {
  required String participantId,
  required int offsetMs,
  required int hostSentMs,
  int upMs = 20,
  int downMs = 20,
  int processingMs = 5,
}) {
  final guestReceivedMs = hostSentMs + upMs + offsetMs;
  final guestSentMs = guestReceivedMs + processingMs;
  final hostReceivedMs = hostSentMs + upMs + processingMs + downMs;
  return clock.registerProbe(
    participantId: participantId,
    hostSentMs: hostSentMs,
    guestReceivedMs: guestReceivedMs,
    guestSentMs: guestSentMs,
    hostReceivedMs: hostReceivedMs,
  );
}

/// Les 5 échanges de la connexion (doc 02 §4), avec un réseau qui bafouille :
/// aller et retour ne durent jamais pareil d'une sonde à l'autre.
void syncWithJitter(
  SyncedClock clock, {
  required String participantId,
  required int offsetMs,
  int startMs = 100000,
  int probes = 5,
}) {
  const jitterUp = [20, 45, 12, 80, 30];
  const jitterDown = [25, 15, 34, 18, 60];
  for (var i = 0; i < probes; i++) {
    sendProbe(
      clock,
      participantId: participantId,
      offsetMs: offsetMs,
      hostSentMs: startMs + i * 200,
      upMs: jitterUp[i % jitterUp.length],
      downMs: jitterDown[i % jitterDown.length],
    );
  }
}

void main() {
  group('ClockProbe', () {
    test('offsetMs applique ((t1−t0)+(t2−t3))/2', () {
      const probe = ClockProbe(
        hostSentMs: 1000,
        guestReceivedMs: 3020,
        guestSentMs: 3025,
        hostReceivedMs: 1050,
      );

      // ((3020−1000) + (3025−1050)) / 2 = (2020 + 1975) / 2 = 1997,5
      expect(probe.offsetMs, 1997.5);
    });

    test("roundTripMs retire le temps de traitement de l'invité", () {
      const probe = ClockProbe(
        hostSentMs: 1000,
        guestReceivedMs: 3020,
        guestSentMs: 3025,
        hostReceivedMs: 1050,
      );

      expect(probe.roundTripMs, 45); // 50 ms de trajet − 5 ms de traitement
    });

    test('égalité structurelle', () {
      const probe = ClockProbe(
        hostSentMs: 1,
        guestReceivedMs: 2,
        guestSentMs: 3,
        hostReceivedMs: 4,
      );

      expect(
        probe,
        const ClockProbe(
          hostSentMs: 1,
          guestReceivedMs: 2,
          guestSentMs: 3,
          hostReceivedMs: 4,
        ),
      );
      expect(
        probe.hashCode,
        const ClockProbe(
          hostSentMs: 1,
          guestReceivedMs: 2,
          guestSentMs: 3,
          hostReceivedMs: 4,
        ).hashCode,
      );
      // Un champ différent à la fois : chaque horodatage compte dans
      // l'identité de la sonde.
      expect(
        probe,
        isNot(
          const ClockProbe(
            hostSentMs: 9,
            guestReceivedMs: 2,
            guestSentMs: 3,
            hostReceivedMs: 4,
          ),
        ),
      );
      expect(
        probe,
        isNot(
          const ClockProbe(
            hostSentMs: 1,
            guestReceivedMs: 9,
            guestSentMs: 3,
            hostReceivedMs: 4,
          ),
        ),
      );
      expect(
        probe,
        isNot(
          const ClockProbe(
            hostSentMs: 1,
            guestReceivedMs: 2,
            guestSentMs: 9,
            hostReceivedMs: 4,
          ),
        ),
      );
      expect(
        probe,
        isNot(
          const ClockProbe(
            hostSentMs: 1,
            guestReceivedMs: 2,
            guestSentMs: 3,
            hostReceivedMs: 9,
          ),
        ),
      );
      expect(probe, isNot(42));
    });
  });

  group('ClockOffset', () {
    test('égalité structurelle', () {
      const offset = ClockOffset(
        offsetMs: 12.5,
        probeCount: 5,
        bestRoundTripMs: 30,
      );

      expect(
        offset,
        const ClockOffset(
          offsetMs: 12.5,
          probeCount: 5,
          bestRoundTripMs: 30,
        ),
      );
      expect(
        offset.hashCode,
        const ClockOffset(
          offsetMs: 12.5,
          probeCount: 5,
          bestRoundTripMs: 30,
        ).hashCode,
      );
      expect(
        offset,
        isNot(
          const ClockOffset(
            offsetMs: 99.5,
            probeCount: 5,
            bestRoundTripMs: 30,
          ),
        ),
      );
      expect(
        offset,
        isNot(
          const ClockOffset(
            offsetMs: 12.5,
            probeCount: 4,
            bestRoundTripMs: 30,
          ),
        ),
      );
      expect(
        offset,
        isNot(
          const ClockOffset(
            offsetMs: 12.5,
            probeCount: 5,
            bestRoundTripMs: 99,
          ),
        ),
      );
      expect(offset, isNot(42));
    });
  });

  group('SyncedClock — précision', () {
    test('réseau symétrique : offset retrouvé exactement', () {
      final clock = SyncedClock();

      syncWithJitter(clock, participantId: 'p-1', offsetMs: 0);
      sendProbe(
        clock,
        participantId: 'p-2',
        offsetMs: 1234,
        hostSentMs: 100000,
      );

      expect(clock.offsetFor('p-2')!.offsetMs, 1234);
    });

    // Le critère chiffré de MVP-09.
    test('offsets simulés de ±2 s corrigés à ±50 ms près, avec jitter', () {
      for (final offsetMs in [-2000, -1500, -300, 0, 300, 1500, 2000]) {
        final clock = SyncedClock();

        syncWithJitter(clock, participantId: 'p-1', offsetMs: offsetMs);

        expect(
          clock.offsetFor('p-1')!.offsetMs,
          closeTo(offsetMs, 50),
          reason: 'offset simulé de $offsetMs ms',
        );
        expect(
          clock.toHostTimeMs(participantId: 'p-1', guestTimeMs: 500000),
          closeTo(500000 - offsetMs, 50),
          reason: 'horodatage corrigé pour un offset de $offsetMs ms',
        );
      }
    });

    test('la médiane écarte un aller-retour ralenti par le Wi-Fi', () {
      final clock = SyncedClock();
      const offsetMs = 1000;

      // Quatre sondes propres…
      for (var i = 0; i < 4; i++) {
        sendProbe(
          clock,
          participantId: 'p-1',
          offsetMs: offsetMs,
          hostSentMs: 100000 + i * 200,
        );
      }
      // …et une cinquième dont l'aller a pris 2 s de plus que le retour :
      // à elle seule, sa mesure est fausse de 1 s.
      sendProbe(
        clock,
        participantId: 'p-1',
        offsetMs: offsetMs,
        hostSentMs: 100800,
        upMs: 2020,
      );

      expect(clock.offsetFor('p-1')!.offsetMs, closeTo(offsetMs, 50));
    });

    test('bestRoundTripMs retient le meilleur aller-retour observé', () {
      final clock = SyncedClock();

      sendProbe(
        clock,
        participantId: 'p-1',
        offsetMs: 0,
        hostSentMs: 100000,
        upMs: 200,
        downMs: 200,
      );
      sendProbe(
        clock,
        participantId: 'p-1',
        offsetMs: 0,
        hostSentMs: 100500,
        upMs: 10,
        downMs: 12,
      );

      expect(clock.offsetFor('p-1')!.bestRoundTripMs, 22);
    });

    test('médiane paire : moyenne des deux mesures centrales', () {
      final clock = SyncedClock();

      // L'erreur d'une sonde vaut (up − down)/2 : ces quatre asymétries
      // donnent des mesures de 980, 990, 1010 et 1020 ms, dont la médiane
      // est la moyenne des deux centrales.
      const asymmetries = [(20, 60), (20, 40), (40, 20), (60, 20)];
      for (final (index, (upMs, downMs)) in asymmetries.indexed) {
        sendProbe(
          clock,
          participantId: 'p-1',
          offsetMs: 1000,
          hostSentMs: 100000 + index * 200,
          upMs: upMs,
          downMs: downMs,
        );
      }

      expect(clock.offsetFor('p-1')!.probeCount, 4);
      expect(clock.offsetFor('p-1')!.offsetMs, 1000);
    });
  });

  group('SyncedClock — cycle de vie', () {
    test('invité jamais mesuré : horodatage rendu tel quel, pas perdu', () {
      final clock = SyncedClock();

      expect(clock.offsetFor('inconnu'), isNull);
      expect(clock.isSynced('inconnu'), isFalse);
      expect(
        clock.toHostTimeMs(participantId: 'inconnu', guestTimeMs: 42000),
        42000,
      );
    });

    test("isSynced ne bascule qu'une fois la série complète", () {
      final clock = SyncedClock();

      for (var i = 0; i < 4; i++) {
        sendProbe(
          clock,
          participantId: 'p-1',
          offsetMs: 500,
          hostSentMs: 100000 + i * 200,
        );
        expect(clock.isSynced('p-1'), isFalse, reason: 'après ${i + 1} sondes');
      }
      sendProbe(
        clock,
        participantId: 'p-1',
        offsetMs: 500,
        hostSentMs: 100800,
      );

      expect(clock.isSynced('p-1'), isTrue);
      expect(clock.offsetFor('p-1')!.probeCount, 5);
    });

    test('une sonde partielle corrige déjà, avant la fin de la série', () {
      final clock = SyncedClock();

      sendProbe(
        clock,
        participantId: 'p-1',
        offsetMs: 1500,
        hostSentMs: 100000,
      );

      expect(clock.isSynced('p-1'), isFalse);
      expect(
        clock.toHostTimeMs(participantId: 'p-1', guestTimeMs: 200000),
        closeTo(198500, 50),
      );
    });

    test('chaque invité a son propre offset', () {
      final clock = SyncedClock();

      syncWithJitter(clock, participantId: 'p-1', offsetMs: 2000);
      syncWithJitter(clock, participantId: 'p-2', offsetMs: -1200);
      syncWithJitter(clock, participantId: 'p-3', offsetMs: 0);

      expect(clock.offsetFor('p-1')!.offsetMs, closeTo(2000, 50));
      expect(clock.offsetFor('p-2')!.offsetMs, closeTo(-1200, 50));
      expect(clock.offsetFor('p-3')!.offsetMs, closeTo(0, 50));
      // Deux invités qui prononcent au même instant réel, sur des horloges
      // décalées de 3,2 s, se retrouvent au même instant hôte.
      expect(
        clock.toHostTimeMs(participantId: 'p-1', guestTimeMs: 502000),
        closeTo(
          clock.toHostTimeMs(participantId: 'p-2', guestTimeMs: 498800),
          50,
        ),
      );
    });

    test('horloge qui dérive : la fenêtre glissante finit par la suivre', () {
      final clock = SyncedClock();

      syncWithJitter(clock, participantId: 'p-1', offsetMs: 1000);
      expect(clock.offsetFor('p-1')!.offsetMs, closeTo(1000, 50));

      // Le téléphone se remet à l'heure en cours de repas : cinq sondes
      // plus tard, plus une seule mesure de l'ancienne horloge ne subsiste.
      syncWithJitter(
        clock,
        participantId: 'p-1',
        offsetMs: 1300,
        startMs: 400000,
      );

      expect(clock.offsetFor('p-1')!.offsetMs, closeTo(1300, 50));
      expect(clock.offsetFor('p-1')!.probeCount, 5);
    });

    test('la fenêtre ne retient que clockProbeCount sondes', () {
      final clock = SyncedClock(
        config: const TranscriptTimingConfig(clockProbeCount: 3),
      );

      syncWithJitter(clock, participantId: 'p-1', offsetMs: 800);

      expect(clock.offsetFor('p-1')!.probeCount, 3);
      expect(clock.isSynced('p-1'), isTrue);
    });

    test('forget oublie un invité, clear les oublie tous', () {
      final clock = SyncedClock();

      syncWithJitter(clock, participantId: 'p-1', offsetMs: 1000);
      syncWithJitter(clock, participantId: 'p-2', offsetMs: 2000);

      clock.forget('p-1');
      expect(clock.offsetFor('p-1'), isNull);
      expect(clock.offsetFor('p-2'), isNotNull);

      clock.clear();
      expect(clock.offsetFor('p-2'), isNull);
    });
  });

  group('SyncedClock — sondes invalides', () {
    test('t3 avant t0 : sonde refusée', () {
      final clock = SyncedClock();

      final result = clock.registerProbe(
        participantId: 'p-1',
        hostSentMs: 1000,
        guestReceivedMs: 1010,
        guestSentMs: 1015,
        hostReceivedMs: 900,
      );

      expect(result.failureOrNull, isA<ClockProbeInvalidFailure>());
      expect(clock.offsetFor('p-1'), isNull);
    });

    test('t2 avant t1 : sonde refusée', () {
      final clock = SyncedClock();

      final result = clock.registerProbe(
        participantId: 'p-1',
        hostSentMs: 1000,
        guestReceivedMs: 1010,
        guestSentMs: 1005,
        hostReceivedMs: 1050,
      );

      expect(result.failureOrNull, isA<ClockProbeInvalidFailure>());
      expect(clock.offsetFor('p-1'), isNull);
    });

    test("traitement invité plus long que l'aller-retour : sonde refusée", () {
      final clock = SyncedClock();

      final result = clock.registerProbe(
        participantId: 'p-1',
        hostSentMs: 1000,
        guestReceivedMs: 5000,
        guestSentMs: 9000, // 4 s de « traitement »…
        hostReceivedMs: 1050, // …pour un aller-retour de 50 ms
      );

      expect(result.failureOrNull, isA<ClockProbeInvalidFailure>());
      expect(clock.offsetFor('p-1'), isNull);
    });

    test('une sonde refusée ne pollue pas la série déjà mesurée', () {
      final clock = SyncedClock();

      syncWithJitter(clock, participantId: 'p-1', offsetMs: 1000);
      clock.registerProbe(
        participantId: 'p-1',
        hostSentMs: 1000,
        guestReceivedMs: 1010,
        guestSentMs: 1015,
        hostReceivedMs: 900,
      );

      expect(clock.offsetFor('p-1')!.offsetMs, closeTo(1000, 50));
      expect(clock.offsetFor('p-1')!.probeCount, 5);
    });

    test("registerProbe rend l'estimation à jour", () {
      final clock = SyncedClock();

      final result = sendProbe(
        clock,
        participantId: 'p-1',
        offsetMs: 700,
        hostSentMs: 100000,
      );

      expect(result, isA<Ok<ClockOffset>>());
      expect(result.valueOrNull!.offsetMs, closeTo(700, 50));
      expect(result.valueOrNull!.probeCount, 1);
    });
  });
}
