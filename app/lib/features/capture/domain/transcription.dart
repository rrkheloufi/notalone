import 'package:meta/meta.dart';

/// Le texte rendu par un moteur STT pour un segment de parole.
///
/// C'est la **seule chose qui quittera ce téléphone** : l'audio du segment
/// meurt avec lui (CLAUDE.md règle 2). [engine] voyagera tel quel dans le
/// champ `engine` du `speech_segment` (doc 02 §4), pour qu'on sache plus tard
/// quel moteur a produit quel texte lors de la calibration MVP-15.
@immutable
class Transcription {
  const Transcription({
    required this.text,
    required this.engine,
    this.isFinal = true,
    this.languageTag = 'fr-FR',
  });

  /// Peut être vide : un segment retenu par le VAD mais où le moteur n'a rien
  /// reconnu (bruit de couverts, rire) n'est pas une panne.
  final String text;

  /// Identifiant libre du moteur ayant produit le texte (`ios_speech_analyzer`,
  /// `android_on_device`…). Chaîne libre, comme le champ du protocole.
  final String engine;

  /// MVP-10 ne rend que des finaux (décidé avec Rayan le 20/07/2026) : le
  /// segment soumis est déjà complet, un partiel n'aurait précédé le final que
  /// de quelques centaines de millisecondes. Le champ existe parce que le
  /// protocole le porte et que le moteur cloud (MVP-14) pourra en émettre.
  final bool isFinal;

  final String languageTag;

  bool get isEmpty => text.trim().isEmpty;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Transcription &&
          other.text == text &&
          other.engine == engine &&
          other.isFinal == isFinal &&
          other.languageTag == languageTag);

  @override
  int get hashCode => Object.hash(text, engine, isFinal, languageTag);

  @override
  String toString() => 'Transcription($engine, "$text")';
}
