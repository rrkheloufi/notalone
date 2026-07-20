import 'package:flutter/foundation.dart';
import 'package:notalone/core/command/command.dart';
import 'package:notalone/core/result/result.dart';
import 'package:notalone/features/onboarding/domain/user_profile_repository.dart';

/// Premier lancement : le prénom, et rien d'autre. Pas de compte, pas de
/// réglage (cf. cowork/01-cadrage-produit.md §3).
class OnboardingViewModel extends ChangeNotifier {
  OnboardingViewModel({required this._profiles});

  final UserProfileRepository _profiles;

  late final Command1<void, String> saveCommand = Command1(_save);

  bool _isSaved = false;
  bool get isSaved => _isSaved;

  String _name = '';

  /// Prénom effectivement enregistré, une fois [saveCommand] passée.
  String get name => _name;

  Future<Result<void>> _save(String name) async {
    final trimmed = name.trim();
    // Le bouton est désactivé tant que le champ est vide ; ce garde-fou évite
    // qu'une validation clavier n'enregistre un prénom blanc.
    if (trimmed.isEmpty) return const Result.ok(null);
    final written = await _profiles.writeName(trimmed);
    switch (written) {
      case Err(:final failure):
        return Result.err(failure);
      case Ok():
        _name = trimmed;
        _isSaved = true;
        notifyListeners();
        return const Result.ok(null);
    }
  }

  @override
  void dispose() {
    saveCommand.dispose();
    super.dispose();
  }
}
