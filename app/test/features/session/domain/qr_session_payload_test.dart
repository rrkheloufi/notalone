import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:notalone/features/session/domain/qr_session_payload.dart';
import 'package:notalone/features/session/domain/session_failure.dart';

const payload = QrSessionPayload(
  sessionName: 'Repas de famille',
  host: '192.168.1.42',
  port: 40123,
  token: 'a3f9c2e1b8d74650',
);

void main() {
  test('round-trip encode → decode exact', () {
    final decoded = QrSessionPayload.decode(payload.encode());
    expect(decoded.valueOrNull, payload);
  });

  test('le JSON encodé contient exactement les champs du doc 02 §4', () {
    final json = jsonDecode(payload.encode()) as Map<String, Object?>;
    expect(
      json.keys,
      unorderedEquals(['version', 'sessionName', 'host', 'port', 'token']),
    );
    expect(json['version'], QrSessionPayload.supportedVersion);
  });

  test('champs inconnus ignorés (tolérance ascendante)', () {
    final raw = jsonEncode({
      'version': 1,
      'sessionName': 'Test',
      'host': '10.0.0.5',
      'port': 8080,
      'token': 'tok',
      'extra': 'nouveau champ v2',
    });
    final decoded = QrSessionPayload.decode(raw);
    expect(decoded.isOk, isTrue);
    expect(decoded.valueOrNull?.host, '10.0.0.5');
  });

  test('version supérieure acceptée si les champs requis sont valides', () {
    final raw = jsonEncode({
      'version': 3,
      'sessionName': 'Test',
      'host': '10.0.0.5',
      'port': 8080,
      'token': 'tok',
    });
    expect(QrSessionPayload.decode(raw).valueOrNull?.version, 3);
  });

  test('JSON illisible → Failure typée, jamais d exception', () {
    final decoded = QrSessionPayload.decode('pas du json {');
    expect(decoded.failureOrNull, isA<QrPayloadMalformedFailure>());
  });

  test('pas un objet JSON → Failure', () {
    expect(
      QrSessionPayload.decode('[1, 2]').failureOrNull,
      isA<QrPayloadMalformedFailure>(),
    );
  });

  test('champ requis manquant → Failure', () {
    for (final missing in ['version', 'sessionName', 'host', 'port', 'token']) {
      final json = jsonDecode(payload.encode()) as Map<String, Object?>
        ..remove(missing);
      final decoded = QrSessionPayload.decode(jsonEncode(json));
      expect(
        decoded.failureOrNull,
        isA<QrPayloadMalformedFailure>(),
        reason: 'champ manquant : $missing',
      );
    }
  });

  test('types invalides → Failure', () {
    final raw = jsonEncode({
      'version': 1,
      'sessionName': 'Test',
      'host': '10.0.0.5',
      'port': '8080',
      'token': 'tok',
    });
    expect(
      QrSessionPayload.decode(raw).failureOrNull,
      isA<QrPayloadMalformedFailure>(),
    );
  });

  test('port hors bornes → Failure', () {
    for (final port in [0, -1, 65536]) {
      final raw = jsonEncode({
        'version': 1,
        'sessionName': 'Test',
        'host': '10.0.0.5',
        'port': port,
        'token': 'tok',
      });
      expect(
        QrSessionPayload.decode(raw).failureOrNull,
        isA<QrPayloadMalformedFailure>(),
        reason: 'port : $port',
      );
    }
  });

  test('host ou token vide → Failure', () {
    for (final overrides in [
      {'host': ''},
      {'token': ''},
    ]) {
      final json = (jsonDecode(payload.encode()) as Map<String, Object?>)
        ..addAll(overrides);
      expect(
        QrSessionPayload.decode(jsonEncode(json)).failureOrNull,
        isA<QrPayloadMalformedFailure>(),
        reason: 'overrides : $overrides',
      );
    }
  });

  test('égalité par valeur', () {
    final other = QrSessionPayload.decode(payload.encode()).valueOrNull;
    expect(other, payload);
    expect(other.hashCode, payload.hashCode);
  });
}
