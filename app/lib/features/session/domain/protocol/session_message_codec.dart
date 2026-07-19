import 'dart:convert';

import 'package:notalone/core/result/result.dart';
import 'package:notalone/features/session/domain/protocol/session_message.dart';
import 'package:notalone/features/session/domain/session_failure.dart';

/// Enveloppe `{v, type, payload}` du protocole de session
/// (cf. cowork/02-architecture.md §4). Tolérance ascendante : champs
/// inconnus ignorés à tous les niveaux, version supérieure acceptée ; un
/// type inconnu produit une [UnknownMessageTypeFailure] distincte que
/// l'appelant peut choisir d'ignorer (message d'une version future).
/// Jamais d'exception : toute entrée invalide produit une `Failure` typée.
abstract final class SessionMessageCodec {
  static const int protocolVersion = 1;

  static final _parsers =
      <String, Result<SessionMessage> Function(Map<String, Object?>)>{
        ClockSync.wireType: ClockSync.fromPayload,
        JoinAck.wireType: JoinAck.fromPayload,
        JoinRequest.wireType: JoinRequest.fromPayload,
        MicStatus.wireType: MicStatus.fromPayload,
        Ping.wireType: Ping.fromPayload,
        Pong.wireType: Pong.fromPayload,
        SessionEnd.wireType: SessionEnd.fromPayload,
        SpeechSegmentDto.wireType: SpeechSegmentDto.fromPayload,
      };

  static String encode(SessionMessage message) => jsonEncode({
    'v': protocolVersion,
    'type': message.type,
    'payload': message.toPayloadJson(),
  });

  static Result<SessionMessage> decode(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return const Result.err(MessageMalformedFailure('JSON illisible'));
    }
    if (decoded is! Map<String, Object?>) {
      return const Result.err(MessageMalformedFailure('objet attendu'));
    }
    final v = decoded['v'];
    final type = decoded['type'];
    final payload = decoded['payload'];
    if (v is! int || v < 1) {
      return const Result.err(
        MessageMalformedFailure('version absente ou invalide'),
      );
    }
    if (type is! String || type.isEmpty) {
      return const Result.err(MessageMalformedFailure('type absent'));
    }
    if (payload is! Map<String, Object?>) {
      return const Result.err(MessageMalformedFailure('payload absent'));
    }
    final parser = _parsers[type];
    if (parser == null) {
      return Result.err(UnknownMessageTypeFailure(type));
    }
    return parser(payload);
  }
}
