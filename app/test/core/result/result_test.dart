import 'package:flutter_test/flutter_test.dart';
import 'package:notalone/core/result/failure.dart';
import 'package:notalone/core/result/result.dart';

final class _TestFailure extends Failure {
  const _TestFailure(super.message);
}

void main() {
  const failure = _TestFailure('boom');

  group('Ok', () {
    test('expose la valeur et les indicateurs', () {
      const result = Result.ok(42);

      expect(result.isOk, isTrue);
      expect(result.isErr, isFalse);
      expect(result.valueOrNull, 42);
      expect(result.failureOrNull, isNull);
    });

    test('égalité par valeur', () {
      expect(const Result.ok(42), const Result.ok(42));
      expect(const Result.ok(42), isNot(const Result.ok(43)));
    });
  });

  group('Err', () {
    test('expose la failure et les indicateurs', () {
      const result = Result<int>.err(failure);

      expect(result.isOk, isFalse);
      expect(result.isErr, isTrue);
      expect(result.valueOrNull, isNull);
      expect(result.failureOrNull, failure);
    });

    test('égalité par failure', () {
      expect(const Result<int>.err(failure), const Result<int>.err(failure));
    });
  });

  group('map', () {
    test('transforme la valeur en cas de succès', () {
      final mapped = const Result.ok(21).map((value) => value * 2);

      expect(mapped, const Result.ok(42));
    });

    test('propage la failure sans appeler la transformation', () {
      var called = false;

      final mapped = const Result<int>.err(failure).map((value) {
        called = true;
        return value * 2;
      });

      expect(called, isFalse);
      expect(mapped, const Result<int>.err(failure));
    });
  });

  group('fold', () {
    test('appelle onOk en cas de succès', () {
      final label = const Result.ok(42).fold(
        onOk: (value) => 'ok:$value',
        onErr: (failure) => 'err:$failure',
      );

      expect(label, 'ok:42');
    });

    test('appelle onErr en cas de failure', () {
      final label = const Result<int>.err(failure).fold(
        onOk: (value) => 'ok:$value',
        onErr: (failure) => 'err:$failure',
      );

      expect(label, 'err:boom');
    });
  });
}
