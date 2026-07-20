import 'package:notalone/core/result/result.dart';

/// Le prénom du convive, seule donnée personnelle du MVP : saisi une fois au
/// premier lancement, modifiable dans les réglages, stocké localement et
/// jamais synchronisé (cf. cowork/03-risques-rgpd-roadmap.md §2).
abstract interface class UserProfileRepository {
  /// Prénom enregistré, ou `null` au premier lancement.
  Future<Result<String?>> readName();

  Future<Result<void>> writeName(String name);
}
