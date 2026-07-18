import 'package:flutter/material.dart';

/// Thème accessibilité de base : contraste maximal clair/sombre
/// (cf. cowork/01-cadrage-produit.md §3). Les tailles XL réglables du
/// transcript arrivent en MVP-12.
abstract final class AppTheme {
  static const Color _seed = Color(0xFF1565C0);

  static ThemeData get light => _build(Brightness.light);

  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) => ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: _seed,
          brightness: brightness,
          contrastLevel: 1,
        ),
      );
}
