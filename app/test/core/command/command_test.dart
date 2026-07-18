import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:notalone/core/command/command.dart';
import 'package:notalone/core/result/failure.dart';
import 'package:notalone/core/result/result.dart';

final class _TestFailure extends Failure {
  const _TestFailure() : super('échec de test');
}

void main() {
  test('succès : running puis completed, résultat exposé', () async {
    final command = Command0<int>(() async => const Result.ok(42));
    final states = <bool>[];
    command.addListener(() => states.add(command.running));

    await command.execute();

    expect(states, [true, false]);
    expect(command.completed, isTrue);
    expect(command.error, isFalse);
    expect(command.result, const Result<int>.ok(42));
  });

  test('échec : error exposé, pas d exception', () async {
    final command = Command0<int>(() async => const Result.err(_TestFailure()));

    await command.execute();

    expect(command.error, isTrue);
    expect(command.completed, isFalse);
    expect(command.result?.failureOrNull, isA<_TestFailure>());
  });

  test('exécutions concurrentes ignorées', () async {
    final gate = Completer<Result<int>>();
    var calls = 0;
    final command = Command0<int>(() {
      calls++;
      return gate.future;
    });

    final first = command.execute();
    final second = command.execute();
    gate.complete(const Result.ok(1));
    await Future.wait([first, second]);

    expect(calls, 1);
  });

  test('clearResult efface le résultat', () async {
    final command = Command0<int>(() async => const Result.ok(1));
    await command.execute();
    command.clearResult();
    expect(command.result, isNull);
    expect(command.completed, isFalse);
  });
}
