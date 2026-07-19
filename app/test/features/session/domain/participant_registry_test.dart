import 'package:flutter_test/flutter_test.dart';
import 'package:notalone/features/session/domain/participant.dart';
import 'package:notalone/features/session/domain/participant_registry.dart';
import 'package:notalone/features/session/domain/session_config.dart';
import 'package:notalone/features/session/domain/session_failure.dart';

/// Identifiants déterministes : `id-0`, `id-1`… pour que les tests parlent
/// d'identités plutôt que d'aléas.
ParticipantRegistry buildRegistry({
  SessionConfig config = const SessionConfig(),
}) {
  var next = 0;
  return ParticipantRegistry(config: config, generateId: () => 'id-${next++}');
}

Participant joinGuest(ParticipantRegistry registry, String name) =>
    registry.join(name: name).valueOrNull!;

void main() {
  group('inscription de l hôte', () {
    test('prend la première couleur et compte comme participant', () {
      final registry = buildRegistry();

      final host = registry.registerHost('Rayan');

      expect(host.isHost, isTrue);
      expect(host.isConnected, isTrue);
      expect(host.colorIndex, 0);
      expect(registry.participants, [host]);
      expect(registry.connected, [host]);
    });
  });

  group('admission des invités', () {
    test('couleurs attribuées dans l ordre après celle de l hôte', () {
      final registry = buildRegistry()..registerHost('Rayan');

      final paul = joinGuest(registry, 'Paul');
      final marie = joinGuest(registry, 'Marie');

      expect(paul.colorIndex, 1);
      expect(marie.colorIndex, 2);
      expect(paul.isHost, isFalse);
      expect(paul.id, isNot(marie.id));
    });

    test('la limite compte l hôte : 8 participants, donc 7 invités', () {
      final registry = buildRegistry()..registerHost('Rayan');
      for (var i = 0; i < 7; i++) {
        expect(registry.join(name: 'invité $i').isOk, isTrue, reason: 'n°$i');
      }

      final refused = registry.join(name: 'le huitième invité');

      expect(refused.failureOrNull, isA<SessionFullFailure>());
      expect(registry.connected, hasLength(8));
      expect(
        (refused.failureOrNull! as SessionFullFailure).maxParticipants,
        8,
      );
    });

    test('la limite suit le SessionConfig', () {
      final registry = buildRegistry(
        config: const SessionConfig(maxParticipants: 2),
      )..registerHost('Rayan');

      expect(registry.join(name: 'Paul').isOk, isTrue);
      expect(
        registry.join(name: 'Marie').failureOrNull,
        isA<SessionFullFailure>(),
      );
    });
  });

  group('déconnexion', () {
    test('conserve l entrée, son id et sa couleur', () {
      final registry = buildRegistry()..registerHost('Rayan');
      final paul = joinGuest(registry, 'Paul');

      final disconnected = registry.markDisconnected(paul.id);

      expect(disconnected!.isConnected, isFalse);
      expect(disconnected.id, paul.id);
      expect(disconnected.colorIndex, paul.colorIndex);
      expect(registry.byId(paul.id), disconnected);
      expect(registry.connected, hasLength(1), reason: 'l hôte seul');
    });

    test('libère une place sans libérer la couleur', () {
      final registry = buildRegistry()..registerHost('Rayan');
      final paul = joinGuest(registry, 'Paul');
      registry.markDisconnected(paul.id);

      final marie = joinGuest(registry, 'Marie');

      expect(marie.colorIndex, isNot(paul.colorIndex));
      expect(registry.byId(paul.id), isNotNull, reason: 'place réservée');
    });

    test('identifiant inconnu ou déjà déconnecté → null', () {
      final registry = buildRegistry()..registerHost('Rayan');
      final paul = joinGuest(registry, 'Paul');
      registry.markDisconnected(paul.id);

      expect(registry.markDisconnected('inconnu'), isNull);
      expect(registry.markDisconnected(paul.id), isNull);
    });
  });

  group('reconnexion', () {
    test('un id connu rend l identité, la couleur et rafraîchit le prénom', () {
      final registry = buildRegistry()..registerHost('Rayan');
      final paul = joinGuest(registry, 'Paul');
      registry
        ..markDisconnected(paul.id)
        ..join(name: 'Marie'); // une autre place est prise entre-temps

      final back = registry
          .join(name: 'Paul-Henri', participantId: paul.id)
          .valueOrNull!;

      expect(back.id, paul.id);
      expect(back.colorIndex, paul.colorIndex);
      expect(back.name, 'Paul-Henri');
      expect(back.isConnected, isTrue);
      expect(registry.participants, hasLength(3), reason: 'pas de doublon');
    });

    test('un id inconnu vaut premier join plutôt qu un refus', () {
      final registry = buildRegistry()..registerHost('Rayan');

      final guest = registry
          .join(name: 'Paul', participantId: 'id-d-une-session-precedente')
          .valueOrNull!;

      expect(guest.id, isNot('id-d-une-session-precedente'));
      expect(guest.colorIndex, 1);
    });

    test(
      'reconnexion avant que le départ soit constaté : acceptée, sans doublon',
      () {
        final registry = buildRegistry()..registerHost('Rayan');
        final paul = joinGuest(registry, 'Paul');

        final back = registry
            .join(name: 'Paul', participantId: paul.id)
            .valueOrNull!;

        expect(back.id, paul.id);
        expect(back.colorIndex, paul.colorIndex);
        expect(registry.participants, hasLength(2));
      },
    );

    test('une session pleine laisse toujours revenir les siens', () {
      // WiFi tombé mais départ pas encore constaté par le keepalive : la
      // limite ne doit pas enfermer dehors un invité déjà admis.
      final registry = buildRegistry()..registerHost('Rayan');
      final paul = joinGuest(registry, 'Paul');
      for (var i = 0; i < 6; i++) {
        joinGuest(registry, 'n°$i');
      }
      expect(registry.connected, hasLength(8), reason: 'session pleine');

      final back = registry.join(name: 'Paul', participantId: paul.id);

      expect(back.valueOrNull?.id, paul.id);
      expect(back.valueOrNull?.colorIndex, paul.colorIndex);
      expect(registry.connected, hasLength(8));
    });
  });

  group('recyclage de couleur quand la palette est saturée', () {
    test('le plus ancien parti cède sa couleur et perd sa réservation', () {
      final registry = buildRegistry()..registerHost('Rayan');
      final guests = [for (var i = 0; i < 7; i++) joinGuest(registry, 'n°$i')];
      final first = guests[0];
      final second = guests[1];
      registry
        ..markDisconnected(first.id)
        ..markDisconnected(second.id);

      final newcomer = joinGuest(registry, 'Nouveau');

      expect(newcomer.colorIndex, first.colorIndex);
      expect(registry.byId(first.id), isNull, reason: 'réservation perdue');
      expect(registry.byId(second.id), isNotNull, reason: 'encore réservée');
    });

    test('celui qui a cédé sa place revient comme un nouvel invité', () {
      final registry = buildRegistry()..registerHost('Rayan');
      final guests = [for (var i = 0; i < 7; i++) joinGuest(registry, 'n°$i')];
      registry.markDisconnected(guests[0].id);
      joinGuest(registry, 'Nouveau'); // recycle la couleur de guests[0]
      registry.markDisconnected(guests[1].id);

      final back = registry
          .join(name: 'n°0', participantId: guests[0].id)
          .valueOrNull!;

      expect(back.id, isNot(guests[0].id));
      expect(back.colorIndex, guests[1].colorIndex);
    });
  });

  group('fin de session', () {
    test('clear efface toute trace des participants', () {
      final registry = buildRegistry()..registerHost('Rayan');
      final paul = joinGuest(registry, 'Paul');
      registry
        ..markDisconnected(paul.id)
        ..clear();

      expect(registry.participants, isEmpty);
      expect(registry.connected, isEmpty);
      expect(registry.byId(paul.id), isNull);
    });
  });

  test('les listes exposées ne sont pas modifiables', () {
    final registry = buildRegistry()..registerHost('Rayan');

    expect(() => registry.participants.clear(), throwsUnsupportedError);
    expect(() => registry.connected.clear(), throwsUnsupportedError);
  });
}
