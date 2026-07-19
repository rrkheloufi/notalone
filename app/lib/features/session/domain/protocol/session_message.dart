import 'package:meta/meta.dart';
import 'package:notalone/core/result/result.dart';
import 'package:notalone/features/session/domain/session_failure.dart';

part 'clock_sync.dart';
part 'join_ack.dart';
part 'join_request.dart';
part 'mic_status.dart';
part 'ping_pong.dart';
part 'session_end.dart';
part 'speech_segment_dto.dart';

/// Message du protocole de session (cf. cowork/02-architecture.md §4) :
/// une sous-classe par `type` d'enveloppe `{v, type, payload}`. Sealed pour
/// garantir des `switch` exhaustifs côté hôte (MVP-05) et invité (MVP-06).
@immutable
sealed class SessionMessage {
  const SessionMessage();

  String get type;

  Map<String, Object?> toPayloadJson();
}
