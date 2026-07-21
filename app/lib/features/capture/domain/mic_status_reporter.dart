import 'package:notalone/features/capture/domain/capture_status.dart';

/// Fait remonter l'état du micro de ce téléphone à qui supervise la session.
///
/// Même rôle que `SegmentPublisher` pour le texte, et même découpe : `capture/`
/// déclare l'interface et pousse dedans, sans jamais savoir si l'état part sur
/// un socket (invité) ou reste dans la mémoire du téléphone (hôte, qui n'a pas
/// de socket vers lui-même). Les deux implémentations sont dans `session/data/`
/// — c'est la session qui consomme la supervision (CLAUDE.md règle 3).
///
/// Nul dans `CaptureViewModel` quand l'écran « mon micro » est ouvert hors
/// session : il n'y a alors personne à qui rendre des comptes.
abstract interface class MicStatusReporter {
  /// Signale un changement d'état. Appelé à chaque transition, pas en boucle :
  /// c'est ce qui tient le critère « coupure du micro visible chez l'hôte en
  /// moins de 10 s » (MVP-13).
  void report(CaptureStatus status);

  Future<void> dispose();
}
