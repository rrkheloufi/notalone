import 'package:flutter_test/flutter_test.dart';
import 'package:notalone/features/session/domain/protocol/session_message.dart';
import 'package:notalone/features/session/domain/protocol/session_message_codec.dart';
import 'package:notalone/features/session/domain/session_failure.dart';

const status = MicStatus(state: MicStatusState.active, batteryPct: 87);

void main() {
  test('payload JSON : exactement les champs du doc 02 §4', () {
    expect(
      status.toPayloadJson().keys,
      unorderedEquals(['state', 'batteryPct']),
    );
  });

  test('round-trip via le codec pour chacun des 3 états', () {
    for (final state in MicStatusState.values) {
      final message = MicStatus(state: state, batteryPct: 42);
      expect(
        SessionMessageCodec.decode(
          SessionMessageCodec.encode(message),
        ).valueOrNull,
        message,
        reason: state.name,
      );
    }
  });

  test('champs inconnus ignorés (tolérance ascendante)', () {
    final payload = status.toPayloadJson()..['charging'] = true;
    expect(MicStatus.fromPayload(payload).valueOrNull, status);
  });

  test('état inconnu (futur protocole) → Failure', () {
    final payload = status.toPayloadJson()..['state'] = 'backgrounded';
    expect(
      MicStatus.fromPayload(payload).failureOrNull,
      isA<MessageMalformedFailure>(),
    );
  });

  test('state manquant → Failure', () {
    final payload = status.toPayloadJson()..remove('state');
    expect(
      MicStatus.fromPayload(payload).failureOrNull,
      isA<MessageMalformedFailure>(),
    );
  });

  // Assoupli en MVP-13 : `batteryPct` était obligatoire, il est désormais
  // facultatif. Une plateforme qui ne sait pas lire sa batterie doit pouvoir
  // dire l'état de son micro — qui est l'information la plus utile des deux —
  // sans inventer un pourcentage. Un `0` par défaut aurait affolé le panneau
  // de supervision de l'hôte sans raison.
  test('batteryPct absent → décodé, batterie inconnue', () {
    final payload = status.toPayloadJson()..remove('batteryPct');
    final decoded = MicStatus.fromPayload(payload).valueOrNull;

    expect(decoded?.state, MicStatusState.active);
    expect(decoded?.batteryPct, isNull);
  });

  test('batterie inconnue : le champ ne part pas sur le fil', () {
    const unknown = MicStatus(state: MicStatusState.active, batteryPct: null);

    expect(unknown.toPayloadJson().keys, unorderedEquals(['state']));
    expect(
      SessionMessageCodec.decode(
        SessionMessageCodec.encode(unknown),
      ).valueOrNull,
      unknown,
    );
  });

  test('types invalides → Failure', () {
    for (final overrides in <Map<String, Object?>>[
      {'state': 1},
      {'batteryPct': 'faible'},
      {'batteryPct': 87.5},
    ]) {
      final payload = status.toPayloadJson()..addAll(overrides);
      expect(
        MicStatus.fromPayload(payload).failureOrNull,
        isA<MessageMalformedFailure>(),
        reason: 'overrides : $overrides',
      );
    }
  });

  test('égalité par valeur', () {
    final other = MicStatus.fromPayload(status.toPayloadJson()).valueOrNull;
    expect(other, status);
    expect(other.hashCode, status.hashCode);
    expect(
      status,
      isNot(const MicStatus(state: MicStatusState.muted, batteryPct: 87)),
    );
  });
}
