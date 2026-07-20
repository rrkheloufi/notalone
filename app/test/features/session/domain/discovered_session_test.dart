import 'package:flutter_test/flutter_test.dart';
import 'package:notalone/core/result/result.dart';
import 'package:notalone/features/session/domain/discovered_session.dart';
import 'package:notalone/features/session/domain/session_failure.dart';

Map<String, String> validAttributes() =>
    DiscoveredSession.attributesFor(sessionName: 'Repas', token: 'tok123');

Result<DiscoveredSession> decode({
  Map<String, String>? attributes,
  String? host = '192.168.1.10',
  int port = 40000,
  String fallbackName = 'nom de service',
}) => DiscoveredSession.fromAdvertisement(
  attributes: attributes ?? validAttributes(),
  host: host,
  port: port,
  fallbackName: fallbackName,
);

void main() {
  group('enregistrement TXT', () {
    test('aller-retour annonce → session découverte', () {
      final decoded = decode().valueOrNull;

      expect(decoded, isNotNull);
      expect(decoded!.sessionName, 'Repas');
      expect(decoded.host, '192.168.1.10');
      expect(decoded.port, 40000);
      expect(decoded.token, 'tok123');
    });

    test('les clés respectent la limite RFC 6763 de 9 caractères', () {
      for (final key in validAttributes().keys) {
        expect(key.length, lessThanOrEqualTo(9), reason: 'clé « $key »');
      }
    });

    test('le token voyage bien dans le TXT (secours du QR)', () {
      expect(validAttributes().values, contains('tok123'));
    });

    test('champs inconnus ignorés, version supérieure acceptée', () {
      final decoded = decode(
        attributes: {
          ...validAttributes(),
          'v': '2',
          'futur': 'champ inconnu de la v1',
        },
      ).valueOrNull;

      expect(decoded?.token, 'tok123');
      expect(decoded?.sessionName, 'Repas');
    });

    test('nom de session absent → repli sur le nom du service mDNS', () {
      final attributes = validAttributes()..remove('name');

      final decoded = decode(
        attributes: attributes,
        fallbackName: 'Conversation de Rayan',
      ).valueOrNull;

      expect(decoded?.sessionName, 'Conversation de Rayan');
    });
  });

  group('annonces inexploitables', () {
    test('version absente → failure typée', () {
      final attributes = validAttributes()..remove('v');

      expect(
        decode(attributes: attributes).failureOrNull,
        isA<DiscoveryRecordMalformedFailure>(),
      );
    });

    test('token absent → failure typée (session non joignable)', () {
      final attributes = validAttributes()..remove('token');

      expect(
        decode(attributes: attributes).failureOrNull,
        isA<DiscoveryRecordMalformedFailure>(),
      );
    });

    test('annonce non résolue (pas d’adresse) → failure typée', () {
      expect(
        decode(host: null).failureOrNull,
        isA<DiscoveryRecordMalformedFailure>(),
      );
      expect(
        decode(host: '').failureOrNull,
        isA<DiscoveryRecordMalformedFailure>(),
      );
    });

    test('port hors bornes → failure typée', () {
      expect(
        decode(port: 0).failureOrNull,
        isA<DiscoveryRecordMalformedFailure>(),
      );
      expect(
        decode(port: 70000).failureOrNull,
        isA<DiscoveryRecordMalformedFailure>(),
      );
    });

    test('annonce d’une autre app (TXT étranger) → failure typée', () {
      expect(
        decode(attributes: {'lib': 'bonsoir'}).failureOrNull,
        isA<DiscoveryRecordMalformedFailure>(),
      );
    });
  });

  test('une session découverte rejoint le même chemin que le QR', () {
    const discovered = DiscoveredSession(
      sessionName: 'Repas',
      host: '192.168.1.10',
      port: 40000,
      token: 'tok123',
    );

    final payload = discovered.toQrPayload();

    expect(payload.sessionName, 'Repas');
    expect(payload.host, '192.168.1.10');
    expect(payload.port, 40000);
    expect(payload.token, 'tok123');
  });

  test('égalité par valeur', () {
    const a = DiscoveredSession(
      sessionName: 'Repas',
      host: '192.168.1.10',
      port: 40000,
      token: 'tok',
    );
    const b = DiscoveredSession(
      sessionName: 'Repas',
      host: '192.168.1.10',
      port: 40000,
      token: 'tok',
    );
    const other = DiscoveredSession(
      sessionName: 'Repas',
      host: '192.168.1.10',
      port: 40001,
      token: 'tok',
    );

    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(other));
  });
}
