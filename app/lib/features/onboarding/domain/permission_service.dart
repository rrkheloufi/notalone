import 'package:notalone/core/result/result.dart';

/// Les deux seules permissions du MVP : le micro pour capter sa propre voix,
/// la caméra pour scanner le QR de la session.
enum AppPermission { microphone, camera }

/// Préfixé `App` pour ne pas collisionner avec le `PermissionStatus` du
/// package dans `data/` — ici on reste en pur Dart.
enum AppPermissionStatus {
  granted,

  /// Refusée, mais le système acceptera de redemander.
  denied,

  /// Refusée sans retour possible : seuls les réglages système la rendront.
  /// iOS ne distingue pas les deux cas aussi nettement qu'Android, d'où le
  /// lien vers les réglages proposé dans les deux situations par l'UI.
  permanentlyDenied,
}

abstract interface class PermissionService {
  /// État courant, sans jamais déclencher de dialogue système.
  Future<Result<AppPermissionStatus>> status(AppPermission permission);

  /// Demande la permission : déclenche le dialogue système si l'OS l'autorise
  /// encore, sinon rend l'état actuel.
  Future<Result<AppPermissionStatus>> request(AppPermission permission);

  Future<Result<void>> openSystemSettings();
}
