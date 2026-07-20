import 'package:notalone/core/result/result.dart';
import 'package:notalone/features/onboarding/domain/onboarding_failure.dart';
import 'package:notalone/features/onboarding/domain/permission_service.dart';
import 'package:permission_handler/permission_handler.dart' as handler;

/// Permissions système via `permission_handler`.
///
/// Sur iOS, la liste des permissions réellement compilées est déduite des clés
/// `NS…UsageDescription` de l'Info.plist (permission_handler_apple ≥ 9.4.8,
/// intégration Swift Package Manager) : rien à configurer dans un Podfile,
/// dont MVP-02 avait montré qu'il cassait le build iPhone.
class PermissionHandlerService implements PermissionService {
  static handler.Permission _map(AppPermission permission) =>
      switch (permission) {
        AppPermission.microphone => handler.Permission.microphone,
        AppPermission.camera => handler.Permission.camera,
      };

  /// `restricted` (contrôle parental, gestion d'entreprise) est traité comme
  /// un refus définitif : l'utilisateur ne peut pas l'accorder depuis l'app.
  static AppPermissionStatus _statusOf(handler.PermissionStatus status) =>
      switch (status) {
        handler.PermissionStatus.granted ||
        handler.PermissionStatus.limited ||
        handler.PermissionStatus.provisional => AppPermissionStatus.granted,
        handler.PermissionStatus.permanentlyDenied ||
        handler.PermissionStatus.restricted =>
          AppPermissionStatus.permanentlyDenied,
        handler.PermissionStatus.denied => AppPermissionStatus.denied,
      };

  @override
  Future<Result<AppPermissionStatus>> status(AppPermission permission) async {
    try {
      return Result.ok(_statusOf(await _map(permission).status));
    } on Exception catch (exception) {
      return Result.err(PermissionUnavailableFailure('$exception'));
    }
  }

  @override
  Future<Result<AppPermissionStatus>> request(AppPermission permission) async {
    try {
      return Result.ok(_statusOf(await _map(permission).request()));
    } on Exception catch (exception) {
      return Result.err(PermissionUnavailableFailure('$exception'));
    }
  }

  @override
  Future<Result<void>> openSystemSettings() async {
    try {
      final opened = await handler.openAppSettings();
      return opened
          ? const Result.ok(null)
          : const Result.err(
              PermissionUnavailableFailure('openAppSettings refusé'),
            );
    } on Exception catch (exception) {
      return Result.err(PermissionUnavailableFailure('$exception'));
    }
  }
}
