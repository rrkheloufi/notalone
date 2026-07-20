import 'package:flutter_test/flutter_test.dart';
import 'package:notalone/features/session/domain/guest_client.dart';

const identity = GuestSession(
  participantId: 'p1',
  colorIndex: 3,
  clockOffsetProbe: 1000,
);

void main() {
  test('égalité par valeur : deux acks identiques valent la même identité', () {
    const same = GuestSession(
      participantId: 'p1',
      colorIndex: 3,
      clockOffsetProbe: 1000,
    );

    expect(identity, same);
    expect(identity.hashCode, same.hashCode);
    expect(identity, identity);
  });

  test('un autre participant, ou une autre couleur, diffère', () {
    expect(
      identity,
      isNot(
        const GuestSession(
          participantId: 'p2',
          colorIndex: 3,
          clockOffsetProbe: 1000,
        ),
      ),
    );
    expect(
      identity,
      isNot(
        const GuestSession(
          participantId: 'p1',
          colorIndex: 4,
          clockOffsetProbe: 1000,
        ),
      ),
    );
    // La probe d'horloge fait partie de l'identité de la connexion : deux
    // `join_ack` successifs ne sont pas le même événement (MVP-09).
    expect(
      identity,
      isNot(
        const GuestSession(
          participantId: 'p1',
          colorIndex: 3,
          clockOffsetProbe: 2000,
        ),
      ),
    );
  });
}
