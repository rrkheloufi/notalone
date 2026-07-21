import 'package:flutter/foundation.dart';
import 'package:notalone/core/command/command.dart';
import 'package:notalone/core/result/result.dart';
import 'package:notalone/features/onboarding/domain/user_profile_repository.dart';
import 'package:notalone/features/transcript/domain/transcript_preferences_repository.dart';
import 'package:notalone/features/transcript/domain/transcript_text_scale.dart';

/// Réglages du MVP : le prénom et la taille du texte.
///
/// La taille passe par le **même** [TranscriptPreferencesRepository] que le fil
/// (MVP-12) : les deux écrans règlent une seule et même préférence, on n'en
/// stocke pas deux copies qui divergeraient. Régler ici puis ouvrir le fil, ou
/// l'inverse, donne le même résultat.
///
/// Le choix du moteur STT viendra en MVP-14, avec le moteur cloud lui-même :
/// l'ajouter aujourd'hui n'offrirait qu'une seule option (décision Rayan,
/// MVP-13).
class SettingsViewModel extends ChangeNotifier {
  SettingsViewModel({required this._profiles, required this._preferences});

  final UserProfileRepository _profiles;
  final TranscriptPreferencesRepository _preferences;

  late final Command0<void> loadCommand = Command0(_load);
  late final Command1<void, String> saveCommand = Command1(_save);
  late final Command1<void, TranscriptTextScale> textScaleCommand =
      Command1(_saveTextScale);

  String _name = '';
  String get name => _name;

  TranscriptTextScale _textScale = TranscriptTextScale.initial;
  TranscriptTextScale get textScale => _textScale;

  /// Les deux lectures sont indépendantes : une préférence de taille illisible
  /// ne doit pas priver l'utilisateur de son prénom, ni l'inverse. C'est
  /// l'échec du prénom qui remonte, parce que c'est le seul réglage dont
  /// l'absence se voit (il s'affiche à côté de ce qu'on dit).
  Future<Result<void>> _load() async {
    final scale = await _preferences.readTextScale();
    _textScale = scale.valueOrNull ?? TranscriptTextScale.initial;
    final read = await _profiles.readName();
    _name = read.valueOrNull ?? '';
    notifyListeners();
    return read.map((_) {});
  }

  Future<Result<void>> _save(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return const Result.ok(null);
    final written = await _profiles.writeName(trimmed);
    switch (written) {
      case Err(:final failure):
        return Result.err(failure);
      case Ok():
        _name = trimmed;
        notifyListeners();
        return const Result.ok(null);
    }
  }

  /// Comme sur le fil : la taille change à l'écran d'abord et se persiste
  /// ensuite — l'aperçu doit suivre le doigt, pas le stockage.
  Future<Result<void>> _saveTextScale(TranscriptTextScale scale) async {
    if (scale == _textScale) return const Result.ok(null);
    _textScale = scale;
    notifyListeners();
    return _preferences.writeTextScale(scale);
  }

  @override
  void dispose() {
    loadCommand.dispose();
    saveCommand.dispose();
    textScaleCommand.dispose();
    super.dispose();
  }
}
