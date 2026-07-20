import 'package:flutter_test/flutter_test.dart';
import 'package:notalone/core/result/result.dart';
import 'package:notalone/features/onboarding/data/shared_preferences_user_profile_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('premier lancement : aucun prénom stocké', () async {
    final repository = SharedPreferencesUserProfileRepository();

    expect(await repository.readName(), const Ok<String?>(null));
  });

  test('le prénom écrit se relit tel quel', () async {
    final repository = SharedPreferencesUserProfileRepository();

    await repository.writeName('Camille');

    expect(await repository.readName(), const Ok<String?>('Camille'));
  });

  test('les espaces autour du prénom sont retirés à l’écriture', () async {
    final repository = SharedPreferencesUserProfileRepository();

    await repository.writeName('  Camille  ');

    expect(await repository.readName(), const Ok<String?>('Camille'));
  });

  test('un prénom stocké vide vaut « pas encore saisi »', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      SharedPreferencesUserProfileRepository.nameKey: '   ',
    });
    final repository = SharedPreferencesUserProfileRepository();

    expect(
      await repository.readName(),
      const Ok<String?>(null),
      reason: 'l’onboarding doit se rejouer plutôt qu’afficher une bulle vide',
    );
  });

  test('le dernier prénom écrit remplace le précédent', () async {
    final repository = SharedPreferencesUserProfileRepository();

    await repository.writeName('Camille');
    await repository.writeName('Paul');

    expect(await repository.readName(), const Ok<String?>('Paul'));
  });
}
