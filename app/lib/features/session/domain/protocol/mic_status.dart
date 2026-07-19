part of 'session_message.dart';

/// États du micro d'un invité (cf. cowork/02-architecture.md §4). « batterie
/// faible » et « déconnecté » (MVP-13) se déduisent de `batteryPct` et du
/// keepalive, pas d'un état dédié. Une valeur inconnue au décodage est un
/// message malformé : un émetteur v2 doit rester compatible v1 sur les enums.
enum MicStatusState { active, interrupted, muted }

/// `mic_status` (invité → hôte) : état du micro + batterie, pour le panneau
/// de supervision de l'hôte (MVP-13).
final class MicStatus extends SessionMessage {
  const MicStatus({required this.state, required this.batteryPct});

  static const wireType = 'mic_status';

  final MicStatusState state;
  final int batteryPct;

  @override
  String get type => wireType;

  @override
  Map<String, Object?> toPayloadJson() => {
    'state': state.name,
    'batteryPct': batteryPct,
  };

  static Result<MicStatus> fromPayload(Map<String, Object?> payload) {
    final state = payload['state'];
    final batteryPct = payload['batteryPct'];
    if (state is! String) {
      return const Result.err(
        MessageMalformedFailure('mic_status : state absent'),
      );
    }
    final parsedState = MicStatusState.values.asNameMap()[state];
    if (parsedState == null) {
      return Result.err(
        MessageMalformedFailure('mic_status : state inconnu « $state »'),
      );
    }
    if (batteryPct is! int) {
      return const Result.err(
        MessageMalformedFailure('mic_status : batteryPct absent'),
      );
    }
    return Result.ok(MicStatus(state: parsedState, batteryPct: batteryPct));
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MicStatus &&
          other.state == state &&
          other.batteryPct == batteryPct);

  @override
  int get hashCode => Object.hash(state, batteryPct);
}
