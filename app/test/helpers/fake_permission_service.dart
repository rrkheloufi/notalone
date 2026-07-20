import 'package:notalone/core/result/failure.dart';
import 'package:notalone/core/result/result.dart';
import 'package:notalone/features/onboarding/domain/permission_service.dart';

/// Permissions simulées : l'état courant, celui que rendra la demande, et les
/// pannes du service.
final class FakePermissionService implements PermissionService {
  FakePermissionService({
    this.current = AppPermissionStatus.denied,
    this.afterRequest,
  });

  AppPermissionStatus current;

  /// Statut rendu par [request] ; à défaut, [current] est inchangé.
  AppPermissionStatus? afterRequest;

  Failure? requestFailure;
  Failure? settingsFailure;

  int requestCount = 0;
  int settingsCount = 0;

  @override
  Future<Result<AppPermissionStatus>> status(AppPermission permission) async =>
      Result.ok(current);

  @override
  Future<Result<AppPermissionStatus>> request(AppPermission permission) async {
    requestCount++;
    final failure = requestFailure;
    if (failure != null) return Result.err(failure);
    current = afterRequest ?? current;
    return Result.ok(current);
  }

  @override
  Future<Result<void>> openSystemSettings() async {
    settingsCount++;
    final failure = settingsFailure;
    return failure != null ? Result.err(failure) : const Result.ok(null);
  }
}
