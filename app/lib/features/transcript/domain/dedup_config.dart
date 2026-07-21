import 'package:meta/meta.dart';

/// Seuils de la déduplication cross-talk (cf. cowork/02-architecture.md §5.3).
///
/// Séparés de `TranscriptTimingConfig` parce qu'ils se calibrent sur d'autres
/// mesures : le temps se règle au chronomètre, ces seuils-là se règlent sur un
/// vrai repas (MVP-15). Les valeurs ci-dessous sont un point de départ
/// raisonné, pas des constantes mesurées — c'est MVP-15 qui les arrêtera.
@immutable
class DedupConfig {
  const DedupConfig({
    this.minOverlapIou = 0.4,
    this.minTextSimilarity = 0.7,
    this.lateDuplicateWindow = const Duration(seconds: 3),
  });

  /// Recouvrement temporel minimal (intersection / union) pour que deux
  /// segments soient candidats au même énoncé.
  ///
  /// Deux micros qui captent la même phrase donnent typiquement un IoU > 0,6 :
  /// leurs VAD ouvrent et ferment à quelques centaines de millisecondes près.
  /// On descend à 0,4 pour le micro lointain, dont le VAD rogne souvent le
  /// début ou la fin de la phrase. En dessous, les deux segments ne coexistent
  /// plus assez pour que le texte tranche quoi que ce soit.
  final double minOverlapIou;

  /// Similarité de Levenshtein normalisée (sur texte nettoyé) au-delà de
  /// laquelle deux segments qui se chevauchent sont le même énoncé.
  ///
  /// C'est ce seuil qui fait tout le travail : deux phrases *différentes*
  /// prononcées en même temps se ressemblent peu (0,2–0,4 en français, où seuls
  /// les mots outils sont partagés), alors que la même phrase captée de loin
  /// revient avec un ou deux mots fautifs — au-dessus de 0,7. Le monter
  /// laisserait passer des doublons ; le baisser fusionnerait deux convives
  /// qui parlent en même temps, ce qui **efface une vraie phrase** : c'est la
  /// faute la plus grave des deux (doc 01 §9).
  final double minTextSimilarity;

  /// Durée pendant laquelle une entrée déjà figée reste candidate à la
  /// déduplication, pour écarter un jumeau qui arrive après elle.
  ///
  /// Le double de la fenêtre de réordonnancement : au-delà, un segment qui
  /// ressemble à un autre n'est plus du cross-talk mais quelqu'un qui répète.
  /// Borne aussi la mémoire — c'est ce qui garantit l'absence de dérive sur
  /// 2 h (critère d'acceptation MVP-11).
  final Duration lateDuplicateWindow;

  int get lateDuplicateWindowMs => lateDuplicateWindow.inMilliseconds;
}
