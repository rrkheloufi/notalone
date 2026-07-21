/// Nettoyage du texte avant comparaison (cf. cowork/02-architecture.md §5.3 :
/// « Levenshtein normalisée sur texte **nettoyé** »).
///
/// Deux moteurs STT — ou le même moteur sur deux micros — rendent la même
/// phrase avec une ponctuation, une casse et parfois des accents différents.
/// Comparer les textes bruts ferait chuter la similarité sur des différences
/// qui ne changent rien à ce qui a été dit.
///
/// Pur Dart, sans `intl` : la table de translittération ci-dessous couvre le
/// français, seule langue du MVP (doc 01 §5).
library;

const Map<String, String> _foldings = {
  'à': 'a', 'â': 'a', 'ä': 'a', 'á': 'a', 'ã': 'a', 'å': 'a',
  'ç': 'c',
  'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
  'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i',
  'ñ': 'n',
  'ò': 'o', 'ó': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o',
  'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u',
  'ý': 'y', 'ÿ': 'y',
  'œ': 'oe', 'æ': 'ae',
};

/// Tout ce qui n'est ni lettre latine, ni chiffre, ni espace : la ponctuation
/// d'un moteur STT est une décision de mise en forme, pas un mot prononcé.
final RegExp _nonAlphanumeric = RegExp('[^a-z0-9 ]');

final RegExp _whitespace = RegExp(r'\s+');

/// Minuscules, accents repliés, ponctuation retirée, espaces compactés.
/// Rend une chaîne sans espace de tête ni de queue, éventuellement vide.
String normalizeForComparison(String text) {
  final buffer = StringBuffer();
  for (final rune in text.toLowerCase().runes) {
    final character = String.fromCharCode(rune);
    buffer.write(_foldings[character] ?? character);
  }
  return buffer
      .toString()
      .replaceAll(_nonAlphanumeric, ' ')
      .replaceAll(_whitespace, ' ')
      .trim();
}
