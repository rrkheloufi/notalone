import 'package:flutter/foundation.dart';
import 'package:notalone/core/command/command.dart';
import 'package:notalone/core/result/result.dart';
import 'package:notalone/features/onboarding/domain/user_profile_repository.dart';

/// Décide de l'écran de démarrage : onboarding au premier lancement, home
/// ensuite (cf. cowork/01-cadrage-produit.md §3 — le prénom n'est demandé
/// qu'une fois).
class AppRootViewModel extends ChangeNotifier {
  AppRootViewModel({required this._profiles});

  final UserProfileRepository _profiles;

  late final Command0<void> loadCommand = Command0(_load);

  bool _isLoaded = false;

  /// Faux tant que le prénom n'a pas été relu : l'app montre un écran neutre
  /// plutôt que de faire clignoter l'onboarding chez quelqu'un qui l'a déjà
  /// rempli.
  bool get isLoaded => _isLoaded;

  String? _name;
  String? get name => _name;

  bool get needsOnboarding => _isLoaded && _name == null;

  Future<Result<void>> _load() async {
    final read = await _profiles.readName();
    // Un stockage illisible se comporte comme un premier lancement : mieux
    // vaut redemander le prénom que bloquer l'accès à la conversation.
    _name = read.valueOrNull;
    _isLoaded = true;
    notifyListeners();
    return read.map((_) {});
  }

  @override
  void dispose() {
    loadCommand.dispose();
    super.dispose();
  }
}
