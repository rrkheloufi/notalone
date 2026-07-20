import 'package:flutter_test/flutter_test.dart';
import 'package:notalone/features/session/domain/protocol/session_close_codes.dart';
import 'package:notalone/features/session/domain/session_failure.dart';

void main() {
  test('chaque code de refus de l’hôte devient un message lisible', () {
    const codes = [
      SessionCloseCodes.invalidToken,
      SessionCloseCodes.sessionFull,
      SessionCloseCodes.joinExpected,
      SessionCloseCodes.sessionEnded,
    ];

    final messages = <String>{};
    for (final code in codes) {
      final message = JoinRefusedFailure(code).message;
      expect(message, isNotEmpty);
      // Pas de code brut sous les yeux d'un convive.
      expect(message, isNot(contains('$code')));
      messages.add(message);
    }
    expect(messages, hasLength(codes.length), reason: 'un motif par code');
  });

  test('code inattendu → message de repli, jamais d’exception', () {
    expect(JoinRefusedFailure(4999).message, contains('4999'));
  });

  test('le code reste lisible par l’UI pour décider de retenter', () {
    final failure = JoinRefusedFailure(SessionCloseCodes.sessionFull);

    expect(failure.closeCode, SessionCloseCodes.sessionFull);
    expect(failure, JoinRefusedFailure(SessionCloseCodes.sessionFull));
    expect(
      failure,
      isNot(JoinRefusedFailure(SessionCloseCodes.invalidToken)),
    );
  });
}
