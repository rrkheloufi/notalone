import 'package:notalone/core/result/failure.dart';
import 'package:notalone/core/result/result.dart';
import 'package:notalone/features/onboarding/domain/user_profile_repository.dart';

/// Stockage du prénom en mémoire, avec pannes injectables.
final class FakeUserProfileRepository implements UserProfileRepository {
  FakeUserProfileRepository({this.name});

  String? name;
  Failure? readFailure;
  Failure? writeFailure;

  /// Prénoms effectivement écrits, dans l'ordre : dit à la fois combien de
  /// fois on a écrit et ce qu'on a écrit.
  final List<String> written = [];

  @override
  Future<Result<String?>> readName() async {
    final failure = readFailure;
    return failure != null ? Result.err(failure) : Result.ok(name);
  }

  @override
  Future<Result<void>> writeName(String name) async {
    final failure = writeFailure;
    if (failure != null) return Result.err(failure);
    written.add(name);
    this.name = name;
    return const Result.ok(null);
  }
}
