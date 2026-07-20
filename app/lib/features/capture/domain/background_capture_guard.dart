import 'package:notalone/core/result/result.dart';

/// Ce qui maintient la capture en vie quand l'invité verrouille son écran
/// (cf. cowork/01-cadrage-produit.md §3 et doc 02 §8).
///
/// Les deux OS n'ont pas besoin de la même chose : Android coupe le micro
/// d'une app d'arrière-plan tant qu'aucun foreground service de type
/// `microphone` ne tourne, alors qu'iOS se contente de `UIBackgroundModes:
/// audio` et de la session audio active que `record` tient déjà. La fabrique
/// de `data/` est le seul endroit qui connaît cette différence (CLAUDE.md
/// règle 7).
abstract interface class BackgroundCaptureGuard {
  /// À appeler **avant** de démarrer le micro : sur Android le service doit
  /// tourner au moment où l'app passe en arrière-plan.
  Future<Result<void>> acquire();

  Future<void> release();

  /// Vraie si l'OS a promis de ne pas mettre l'app en sommeil. Fausse ne
  /// bloque rien : la capture démarre quand même, l'exemption n'est qu'une
  /// assurance contre les optimisations OEM agressives (doc 03 R5).
  Future<bool> isBatteryOptimizationDisabled();

  /// Ouvre la demande d'exemption d'optimisation batterie. Sans effet là où
  /// la notion n'existe pas.
  Future<void> requestBatteryOptimizationExemption();
}
