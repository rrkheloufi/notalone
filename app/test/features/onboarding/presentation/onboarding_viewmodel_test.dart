import 'package:flutter_test/flutter_test.dart';
import 'package:notalone/features/onboarding/domain/onboarding_failure.dart';
import 'package:notalone/features/onboarding/presentation/onboarding_viewmodel.dart';

import '../../../helpers/fake_user_profile_repository.dart';

void main() {
  test('le prénom saisi est persisté et l’onboarding se termine', () async {
    final profiles = FakeUserProfileRepository();
    final viewModel = OnboardingViewModel(profiles: profiles);

    await viewModel.saveCommand.execute('Camille');

    expect(profiles.written, ['Camille']);
    expect(viewModel.isSaved, isTrue);
    expect(viewModel.name, 'Camille');
  });

  test('les espaces autour du prénom sont retirés', () async {
    final profiles = FakeUserProfileRepository();
    final viewModel = OnboardingViewModel(profiles: profiles);

    await viewModel.saveCommand.execute('  Camille  ');

    expect(profiles.written, ['Camille']);
    expect(viewModel.name, 'Camille');
  });

  test('un prénom vide n’est jamais enregistré', () async {
    final profiles = FakeUserProfileRepository();
    final viewModel = OnboardingViewModel(profiles: profiles);

    await viewModel.saveCommand.execute('   ');

    expect(profiles.written, isEmpty);
    expect(viewModel.isSaved, isFalse);
  });

  test('écriture impossible : l’onboarding ne se termine pas', () async {
    final profiles = FakeUserProfileRepository()
      ..writeFailure = const ProfileStorageFailure('disque plein');
    final viewModel = OnboardingViewModel(profiles: profiles);

    await viewModel.saveCommand.execute('Camille');

    expect(viewModel.isSaved, isFalse);
    expect(viewModel.saveCommand.error, isTrue);
  });
}
