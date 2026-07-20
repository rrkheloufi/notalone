import 'package:flutter_test/flutter_test.dart';
import 'package:notalone/features/onboarding/domain/onboarding_failure.dart';
import 'package:notalone/features/settings/presentation/settings_viewmodel.dart';

import '../../../helpers/fake_user_profile_repository.dart';

void main() {
  test('les réglages ouvrent sur le prénom courant', () async {
    final viewModel = SettingsViewModel(
      profiles: FakeUserProfileRepository(name: 'Camille'),
    );

    await viewModel.loadCommand.execute();

    expect(viewModel.name, 'Camille');
  });

  test('le nouveau prénom est persisté', () async {
    final profiles = FakeUserProfileRepository(name: 'Camille');
    final viewModel = SettingsViewModel(profiles: profiles);

    await viewModel.saveCommand.execute('  Paul ');

    expect(profiles.written, ['Paul']);
    expect(viewModel.name, 'Paul');
  });

  test('un prénom vide ne remplace pas l’ancien', () async {
    final profiles = FakeUserProfileRepository(name: 'Camille');
    final viewModel = SettingsViewModel(profiles: profiles);

    await viewModel.saveCommand.execute('  ');

    expect(profiles.written, isEmpty);
    expect(profiles.name, 'Camille');
  });

  test('écriture impossible : la commande signale l’échec', () async {
    final profiles = FakeUserProfileRepository(name: 'Camille')
      ..writeFailure = const ProfileStorageFailure('disque plein');
    final viewModel = SettingsViewModel(profiles: profiles);

    await viewModel.saveCommand.execute('Paul');

    expect(viewModel.saveCommand.error, isTrue);
    expect(viewModel.name, isNot('Paul'));
  });
}
