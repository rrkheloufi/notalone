import 'package:flutter/foundation.dart';
import 'package:notalone/core/command/command.dart';
import 'package:notalone/core/result/result.dart';
import 'package:notalone/features/onboarding/domain/permission_service.dart';

/// Issue de la porte de permission, telle que la lit l'écran appelant.
enum PermissionOutcome {
  granted,

  /// L'utilisateur poursuit sans accorder la permission. Le sens appartient à
  /// l'appelant : continuer sans capter sa voix (micro) ou chercher la session
  /// sur le réseau (caméra).
  skipped,

  /// Retour en arrière : on ne va nulle part.
  cancelled,
}

/// Écran d'explication d'une permission : une phrase sur l'usage réel, la
/// demande système, et de quoi s'en sortir en cas de refus
/// (cf. cowork/01-cadrage-produit.md §3).
class PermissionGateViewModel extends ChangeNotifier {
  PermissionGateViewModel({required this._service, required this.permission});

  final PermissionService _service;
  final AppPermission permission;

  late final Command0<void> requestCommand = Command0(_request);
  late final Command0<void> openSettingsCommand = Command0(_openSettings);

  AppPermissionStatus? _status;

  /// Nul tant que rien n'a été demandé depuis cet écran.
  AppPermissionStatus? get status => _status;

  bool get isGranted => _status == AppPermissionStatus.granted;

  bool get isRefused =>
      _status == AppPermissionStatus.denied ||
      _status == AppPermissionStatus.permanentlyDenied;

  /// Redemander n'a de sens que si le système accepte encore d'afficher son
  /// dialogue. iOS ne l'annonce pas toujours, d'où le lien vers les réglages
  /// proposé dès le premier refus.
  bool get canRequestAgain => _status != AppPermissionStatus.permanentlyDenied;

  Future<Result<void>> _request() async {
    final requested = await _service.request(permission);
    switch (requested) {
      case Err(:final failure):
        // Service injoignable : on n'invente pas d'autorisation, l'écran
        // laisse l'utilisateur passer outre ou ouvrir les réglages.
        _status = AppPermissionStatus.denied;
        notifyListeners();
        return Result.err(failure);
      case Ok(value: final status):
        _status = status;
        notifyListeners();
        return const Result.ok(null);
    }
  }

  Future<Result<void>> _openSettings() => _service.openSystemSettings();

  @override
  void dispose() {
    requestCommand.dispose();
    openSettingsCommand.dispose();
    super.dispose();
  }
}
