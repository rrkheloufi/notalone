import 'package:flutter/material.dart';

/// Couleurs stables attribuées aux locuteurs via le `colorIndex` du protocole
/// (cf. cowork/02-architecture.md §4). Palette provisoire, calibrée en MVP-12.
abstract final class SpeakerColors {
  static const List<Color> palette = [
    Color(0xFF1565C0), // bleu
    Color(0xFFE65100), // orange
    Color(0xFF2E7D32), // vert
    Color(0xFF6A1B9A), // violet
    Color(0xFF00838F), // cyan foncé
    Color(0xFFAD1457), // rose foncé
    Color(0xFF4E342E), // brun
    Color(0xFF37474F), // bleu-gris
  ];

  static Color at(int colorIndex) => palette[colorIndex % palette.length];
}
