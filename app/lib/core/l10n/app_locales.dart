import 'package:flutter/widgets.dart';

/// FR uniquement au MVP ; la v1 ajoutera l'anglais (cf. doc 01 §7).
abstract final class AppLocales {
  static const List<Locale> supported = [Locale('fr')];

  static const Locale fallback = Locale('fr');

  static const String translationsPath = 'assets/translations';
}
