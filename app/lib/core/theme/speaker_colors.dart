import 'package:flutter/material.dart';

/// Couleurs stables attribuées aux locuteurs via le `colorIndex` du protocole
/// (cf. cowork/02-architecture.md §4). Huit teintes, comme les huit places
/// d'une session (décision MVP-05).
///
/// Deux palettes et non une : la même teinte ne peut pas être lisible à la
/// fois sur fond clair et sur fond sombre. [at] donne le **remplissage** (une
/// pastille, du texte blanc par-dessus), [onSurface] donne la teinte à poser
/// **en texte** sur le fond de l'écran, choisie pour dépasser 4,5:1 dans les
/// deux thèmes — le lecteur de ce fil est souvent presbyte autant que sourd.
///
/// La couleur ne porte jamais seule l'information : chaque bulle est aussi
/// coiffée du prénom en toutes lettres.
abstract final class SpeakerColors {
  /// Teintes pleines, pensées pour recevoir du blanc par-dessus.
  static const List<Color> palette = [
    Color(0xFF1565C0), // bleu
    Color(0xFFA34000), // orange
    Color(0xFF2E7D32), // vert
    Color(0xFF6A1B9A), // violet
    Color(0xFF00838F), // cyan foncé
    Color(0xFFAD1457), // rose foncé
    Color(0xFF4E342E), // brun
    Color(0xFF37474F), // bleu-gris
  ];

  /// Les mêmes teintes assombries pour rester lisibles en texte sur fond clair.
  static const List<Color> _onLight = [
    Color(0xFF0D47A1),
    Color(0xFF8A3600),
    Color(0xFF1B5E20),
    Color(0xFF4A148C),
    Color(0xFF00595F),
    Color(0xFF880E4F),
    Color(0xFF3E2723),
    Color(0xFF263238),
  ];

  /// Et éclaircies pour le mode sombre, où les précédentes disparaîtraient.
  static const List<Color> _onDark = [
    Color(0xFF90CAF9),
    Color(0xFFFFB74D),
    Color(0xFFA5D6A7),
    Color(0xFFCE93D8),
    Color(0xFF80DEEA),
    Color(0xFFF48FB1),
    Color(0xFFBCAAA4),
    Color(0xFFB0BEC5),
  ];

  static Color at(int colorIndex) => palette[_wrap(colorIndex)];

  static Color onSurface(int colorIndex, Brightness brightness) =>
      brightness == Brightness.dark
      ? _onDark[_wrap(colorIndex)]
      : _onLight[_wrap(colorIndex)];

  /// Le modulo accepte un index négatif : un `colorIndex` aberrant venu du fil
  /// doit donner une couleur, pas une exception sous les yeux du lecteur.
  static int _wrap(int colorIndex) => colorIndex.abs() % palette.length;
}
