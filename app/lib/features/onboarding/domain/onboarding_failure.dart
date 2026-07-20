import 'package:notalone/core/result/failure.dart';

/// Le stockage local du prénom est inaccessible (disque plein, plateforme qui
/// refuse). Le parcours continue : le prénom sera redemandé au lancement
/// suivant plutôt que de bloquer l'app.
class ProfileStorageFailure extends Failure {
  const ProfileStorageFailure(super.message);
}

/// Le service de permissions n'a pas répondu (plateforme non supportée, canal
/// indisponible). Distinct d'un refus, qui est un statut et non une erreur.
class PermissionUnavailableFailure extends Failure {
  const PermissionUnavailableFailure(super.message);
}
