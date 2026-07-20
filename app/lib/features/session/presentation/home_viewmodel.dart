import 'package:flutter/foundation.dart';
import 'package:notalone/core/command/command.dart';
import 'package:notalone/core/result/result.dart';
import 'package:notalone/features/onboarding/domain/user_profile_repository.dart';

/// Écran d'accueil : deux chemins, créer ou rejoindre
/// (cf. cowork/01-cadrage-produit.md §3).
class HomeViewModel extends ChangeNotifier {
  HomeViewModel({required this._profiles, required this._name});

  final UserProfileRepository _profiles;

  late final Command0<void> reloadCommand = Command0(_reload);

  String _name;

  /// Prénom du convive, transmis tel quel au salon hôte et au parcours invité.
  String get name => _name;

  /// Relu au retour des réglages, seul endroit où le prénom change.
  Future<Result<void>> _reload() async {
    final read = await _profiles.readName();
    final stored = read.valueOrNull;
    if (stored != null && stored != _name) {
      _name = stored;
      notifyListeners();
    }
    return read.map((_) {});
  }

  @override
  void dispose() {
    reloadCommand.dispose();
    super.dispose();
  }
}
