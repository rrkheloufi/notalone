import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:notalone/core/result/result.dart';
import 'package:notalone/features/session/domain/session_failure.dart';

/// Payload du QR code de découverte (cf. cowork/02-architecture.md §4) :
/// JSON `{version, sessionName, host, port, token}`. Comme pour le protocole
/// de session, les champs inconnus sont ignorés et une version supérieure
/// est acceptée tant que les champs requis sont valides (tolérance
/// ascendante).
@immutable
class QrSessionPayload {
  const QrSessionPayload({
    required this.sessionName,
    required this.host,
    required this.port,
    required this.token,
    this.version = supportedVersion,
  });

  static const int supportedVersion = 1;

  final int version;
  final String sessionName;
  final String host;
  final int port;
  final String token;

  String encode() => jsonEncode({
    'version': version,
    'sessionName': sessionName,
    'host': host,
    'port': port,
    'token': token,
  });

  static Result<QrSessionPayload> decode(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return const Result.err(QrPayloadMalformedFailure('JSON illisible'));
    }
    if (decoded is! Map<String, Object?>) {
      return const Result.err(QrPayloadMalformedFailure('objet attendu'));
    }
    final version = decoded['version'];
    final sessionName = decoded['sessionName'];
    final host = decoded['host'];
    final port = decoded['port'];
    final token = decoded['token'];
    if (version is! int || version < 1) {
      return const Result.err(QrPayloadMalformedFailure('version absente'));
    }
    if (sessionName is! String) {
      return const Result.err(QrPayloadMalformedFailure('sessionName absent'));
    }
    if (host is! String || host.isEmpty) {
      return const Result.err(QrPayloadMalformedFailure('host absent'));
    }
    if (port is! int || port < 1 || port > 65535) {
      return const Result.err(QrPayloadMalformedFailure('port invalide'));
    }
    if (token is! String || token.isEmpty) {
      return const Result.err(QrPayloadMalformedFailure('token absent'));
    }
    return Result.ok(
      QrSessionPayload(
        version: version,
        sessionName: sessionName,
        host: host,
        port: port,
        token: token,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is QrSessionPayload &&
          other.version == version &&
          other.sessionName == sessionName &&
          other.host == host &&
          other.port == port &&
          other.token == token);

  @override
  int get hashCode => Object.hash(version, sessionName, host, port, token);
}
