/// Les trois tailles de lecture du fil (cf. cowork/01-cadrage-produit.md §3 :
/// « tailles de police réglables (jusqu'à très grande) »).
///
/// Pur Dart, dans `domain/`, parce que la taille choisie est une **préférence
/// persistée** et non un détail de rendu : c'est elle qui traverse le
/// repository, et l'écran ne fait que la traduire en `TextStyle`.
///
/// Les valeurs sont en pixels logiques. [maximum] vise le critère « lisible à
/// 60 cm » : à cette distance une hauteur de capitale d'environ 3 mm est le
/// plancher confortable, soit ~44 px logiques sur un mobile ordinaire. Les deux
/// autres échelonnent vers le bas sans jamais descendre sous la taille
/// courante d'un corps de texte — le lecteur de ce fil est malentendant, pas
/// pressé de faire tenir beaucoup de mots à l'écran.
enum TranscriptTextScale {
  large(bodySize: 26, speakerSize: 18),
  extraLarge(bodySize: 34, speakerSize: 22),
  maximum(bodySize: 44, speakerSize: 26);

  const TranscriptTextScale({
    required this.bodySize,
    required this.speakerSize,
  });

  /// Taille du texte de la prise de parole elle-même.
  final double bodySize;

  /// Taille du prénom qui coiffe la bulle. Volontairement plus petite : c'est
  /// un repère, la phrase est ce qui se lit.
  final double speakerSize;

  /// Interligne généreux : à 44 px, des lignes serrées se confondent.
  double get lineHeight => 1.3;

  static const TranscriptTextScale initial = TranscriptTextScale.extraLarge;

  bool get hasLarger => this != values.last;

  bool get hasSmaller => this != values.first;

  /// Rend la taille suivante, ou soi-même aux extrémités : le bouton se grise
  /// plutôt que de boucler sur la plus petite (cf. [hasLarger]/[hasSmaller]).
  TranscriptTextScale get larger =>
      hasLarger ? values[index + 1] : this;

  TranscriptTextScale get smaller =>
      hasSmaller ? values[index - 1] : this;

  /// Relecture depuis le stockage. Une valeur inconnue — réglage écrit par une
  /// version ultérieure, préférence corrompue — retombe sur [initial] plutôt
  /// que d'échouer : le fil doit s'ouvrir quoi qu'il arrive.
  static TranscriptTextScale fromName(String? name) =>
      values.where((scale) => scale.name == name).firstOrNull ?? initial;
}
