part of 'session_message.dart';

/// `clock_sync` (aller-retour ×5 à la connexion) : échange type NTP.
/// L'hôte envoie `{seq, tHostSentMs}` ; l'invité renvoie le même message
/// complété de `{tGuestReceivedMs, tGuestSentMs}` (toujours ensemble).
/// À la réception l'hôte mesure t3 et calcule l'offset
/// `((t1−t0)+(t2−t3))/2`, médiane sur les 5 échanges (MVP-09).
final class ClockSync extends SessionMessage {
  const ClockSync({
    required this.seq,
    required this.tHostSentMs,
    this.tGuestReceivedMs,
    this.tGuestSentMs,
  }) : assert(
         (tGuestReceivedMs == null) == (tGuestSentMs == null),
         'tGuestReceivedMs et tGuestSentMs vont ensemble',
       );

  static const wireType = 'clock_sync';

  final int seq;
  final int tHostSentMs;
  final int? tGuestReceivedMs;
  final int? tGuestSentMs;

  bool get isReply => tGuestReceivedMs != null;

  @override
  String get type => wireType;

  @override
  Map<String, Object?> toPayloadJson() => {
    'seq': seq,
    'tHostSentMs': tHostSentMs,
    if (tGuestReceivedMs != null) 'tGuestReceivedMs': tGuestReceivedMs,
    if (tGuestSentMs != null) 'tGuestSentMs': tGuestSentMs,
  };

  static Result<ClockSync> fromPayload(Map<String, Object?> payload) {
    final seq = payload['seq'];
    final tHostSentMs = payload['tHostSentMs'];
    final guestReceived = payload['tGuestReceivedMs'];
    final guestSent = payload['tGuestSentMs'];
    if (seq is! int) {
      return const Result.err(
        MessageMalformedFailure('clock_sync : seq absent'),
      );
    }
    if (tHostSentMs is! int) {
      return const Result.err(
        MessageMalformedFailure('clock_sync : tHostSentMs absent'),
      );
    }
    if ((guestReceived == null) != (guestSent == null)) {
      return const Result.err(
        MessageMalformedFailure('clock_sync : champs invité incomplets'),
      );
    }
    int? tGuestReceivedMs;
    int? tGuestSentMs;
    if (guestReceived != null) {
      if (guestReceived is! int || guestSent is! int) {
        return const Result.err(
          MessageMalformedFailure('clock_sync : champs invité invalides'),
        );
      }
      tGuestReceivedMs = guestReceived;
      tGuestSentMs = guestSent;
    }
    return Result.ok(
      ClockSync(
        seq: seq,
        tHostSentMs: tHostSentMs,
        tGuestReceivedMs: tGuestReceivedMs,
        tGuestSentMs: tGuestSentMs,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ClockSync &&
          other.seq == seq &&
          other.tHostSentMs == tHostSentMs &&
          other.tGuestReceivedMs == tGuestReceivedMs &&
          other.tGuestSentMs == tGuestSentMs);

  @override
  int get hashCode =>
      Object.hash(seq, tHostSentMs, tGuestReceivedMs, tGuestSentMs);
}
