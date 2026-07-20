import 'package:flutter/foundation.dart';
import 'package:notalone/core/command/command.dart';
import 'package:notalone/core/result/result.dart';
import 'package:notalone/features/onboarding/domain/user_profile_repository.dart';

/// Réglages du MVP : le prénom seul. Le moteur STT et la taille du texte
/// viendront s'ajouter ici en MVP-13.
class SettingsViewModel extends ChangeNotifier {
  SettingsViewModel({required this._profiles});

  final UserProfileRepository _profiles;

  late final Command0<void> loadCommand = Command0(_load);
  late final Command1<void, String> saveCommand = Command1(_save);

  String _name = '';
  String get name => _name;

  Future<Result<void>> _load() async {
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

  @override
  void dispose() {
    loadCommand.dispose();
    saveCommand.dispose();
    super.dispose();
  }
}
