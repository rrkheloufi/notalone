/// Empêche l'écran de l'hôte de s'éteindre pendant qu'il affiche le fil.
///
/// Sans cela le lecteur devrait réveiller son téléphone toutes les trente
/// secondes pour suivre une conversation — il perdrait justement ce qui a été
/// dit pendant qu'il le rallume. Outil de plateforme, donc interface ici et
/// implémentation dans `data/` (CLAUDE.md règle 3).
///
/// Les deux opérations sont volontairement tolérantes : un verrou d'écran
/// refusé par l'OS ne doit jamais empêcher le fil de s'afficher, c'est un
/// confort, pas une condition.
abstract interface class ScreenWakeLock {
  Future<void> enable();

  Future<void> release();
}
