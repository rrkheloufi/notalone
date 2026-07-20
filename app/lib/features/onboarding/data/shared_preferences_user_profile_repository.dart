import 'package:notalone/core/result/result.dart';
import 'package:notalone/features/onboarding/domain/onboarding_failure.dart';
import 'package:notalone/features/onboarding/domain/user_profile_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Prénom persisté localement via `shared_preferences` (doc 02 §9). Rien
/// d'autre n'est stocké : le transcript reste éphémère.
class SharedPreferencesUserProfileRepository implements UserProfileRepository {
  static const String nameKey = 'user.name';

  @override
  Future<Result<String?>> readName() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final stored = preferences.getString(nameKey)?.trim();
      // Un prénom vide vaut « pas encore saisi » : l'onboarding se rejoue
      // plutôt que d'afficher une bulle sans nom chez le lecteur.
      return Result.ok(stored == null || stored.isEmpty ? null : stored);
    } on Exception catch (exception) {
      return Result.err(ProfileStorageFailure('$exception'));
    }
  }

  @override
  Future<Result<void>> writeName(String name) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(nameKey, name.trim());
      return const Result.ok(null);
    } on Exception catch (exception) {
      return Result.err(ProfileStorageFailure('$exception'));
    }
  }
}
