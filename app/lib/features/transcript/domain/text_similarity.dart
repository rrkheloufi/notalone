/// Similarité de textes pour la déduplication cross-talk
/// (cf. cowork/02-architecture.md §5.3). Attend des chaînes déjà passées par
/// `normalizeForComparison`.
library;

import 'dart:math';

/// Distance d'édition. [maxDistance] permet d'abandonner dès qu'il est certain
/// que le seuil ne sera pas tenu ; la valeur rendue vaut alors `maxDistance+1`,
/// suffisante pour conclure mais **pas** la distance réelle.
int levenshteinDistance(String a, String b, {int? maxDistance}) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;

  var previous = List<int>.generate(b.length + 1, (index) => index);
  var current = List<int>.filled(b.length + 1, 0);

  for (var i = 1; i <= a.length; i++) {
    current[0] = i;
    var rowMin = i;
    final aUnit = a.codeUnitAt(i - 1);
    for (var j = 1; j <= b.length; j++) {
      final substitution = previous[j - 1] + (aUnit == b.codeUnitAt(j - 1)
          ? 0
          : 1);
      final deletion = previous[j] + 1;
      final insertion = current[j - 1] + 1;
      final best = min(substitution, min(deletion, insertion));
      current[j] = best;
      if (best < rowMin) rowMin = best;
    }
    // Toute la ligne dépasse déjà le budget : les lignes suivantes ne peuvent
    // que croître, la réponse est acquise.
    if (maxDistance != null && rowMin > maxDistance) return maxDistance + 1;
    final swap = previous;
    previous = current;
    current = swap;
  }
  return previous[b.length];
}

/// `1 − distance / longueur du plus long`, dans [0;1]. Deux chaînes vides sont
/// identiques (1), une chaîne vide face à une autre ne l'est pas du tout (0).
double normalizedSimilarity(String a, String b) {
  final longest = max(a.length, b.length);
  if (longest == 0) return 1;
  return 1 - levenshteinDistance(a, b) / longest;
}

/// `normalizedSimilarity(a, b) >= threshold`, sans payer la distance complète.
///
/// Deux raccourcis exacts avant le calcul quadratique — la déduplication
/// compare chaque segment à tous ceux de la fenêtre, et un repas de 2 h en
/// produit quelques milliers (critère « 8 flux × 2 h sans dérive ») :
/// 1. l'écart de longueur borne la distance par le bas, donc la similarité par
///    le haut : deux textes de tailles trop différentes sont éliminés en O(1) ;
/// 2. au-delà, la distance s'abandonne dès qu'elle dépasse le budget du seuil.
bool isSimilarAtLeast(String a, String b, double threshold) {
  final longest = max(a.length, b.length);
  if (longest == 0) return threshold <= 1;
  final shortest = min(a.length, b.length);
  if (shortest / longest < threshold) return false;
  final maxDistance = ((1 - threshold) * longest).floor();
  return levenshteinDistance(a, b, maxDistance: maxDistance) <= maxDistance;
}
