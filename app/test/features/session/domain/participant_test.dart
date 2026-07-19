import 'package:flutter_test/flutter_test.dart';
import 'package:notalone/features/session/domain/participant.dart';

const paul = Participant(
  id: 'a3f9c2e1b8d74650',
  name: 'Paul',
  colorIndex: 1,
  isHost: false,
  isConnected: true,
);

void main() {
  test('égalité par valeur', () {
    expect(
      paul,
      const Participant(
        id: 'a3f9c2e1b8d74650',
        name: 'Paul',
        colorIndex: 1,
        isHost: false,
        isConnected: true,
      ),
    );
    expect(paul.hashCode, isNot(paul.copyWith(isConnected: false).hashCode));
  });

  test('chaque champ distingue deux participants', () {
    expect(paul, isNot(paul.copyWith(name: 'Marie')));
    expect(paul, isNot(paul.copyWith(isConnected: false)));
  });

  test('copyWith ne touche ni l identité ni la couleur ni le rôle', () {
    final renamed = paul.copyWith(name: 'Paul-Henri', isConnected: false);

    expect(renamed.id, paul.id);
    expect(renamed.colorIndex, paul.colorIndex);
    expect(renamed.isHost, paul.isHost);
    expect(renamed.name, 'Paul-Henri');
    expect(renamed.isConnected, isFalse);
  });

  test('copyWith sans argument conserve tout', () {
    expect(paul.copyWith(), paul);
  });

  test('toString mentionne le prénom, utile aux journaux de session', () {
    expect(paul.toString(), contains('Paul'));
  });
}
