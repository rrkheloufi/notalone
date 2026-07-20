import 'package:flutter_test/flutter_test.dart';
import 'package:notalone/features/onboarding/domain/onboarding_failure.dart';
import 'package:notalone/features/onboarding/presentation/app_root_viewmodel.dart';

import '../../../helpers/fake_user_profile_repository.dart';

void main() {
  test('avant lecture, aucun écran n’est décidé', () {
    final viewModel = AppRootViewModel(profiles: FakeUserProfileRepository());

    expect(viewModel.isLoaded, isFalse);
    expect(viewModel.needsOnboarding, isFalse);
  });

  test('premier lancement : pas de prénom → onboarding', () async {
    final viewModel = AppRootViewModel(profiles: FakeUserProfileRepository());

    await viewModel.loadCommand.execute();

    expect(viewModel.isLoaded, isTrue);
    expect(viewModel.needsOnboarding, isTrue);
    expect(viewModel.name, isNull);
  });

  test('lancements suivants : prénom connu → home directe', () async {
    final viewModel = AppRootViewModel(
      profiles: FakeUserProfileRepository(name: 'Camille'),
    );

    await viewModel.loadCommand.execute();

    expect(viewModel.needsOnboarding, isFalse);
    expect(viewModel.name, 'Camille');
  });

  test(
    'stockage illisible : on redemande le prénom plutôt que de bloquer',
    () async {
      final profiles = FakeUserProfileRepository(name: 'Camille')
        ..readFailure = const ProfileStorageFailure('disque plein');
      final viewModel = AppRootViewModel(profiles: profiles);

      await viewModel.loadCommand.execute();

      expect(
        viewModel.isLoaded,
        isTrue,
        reason: 'jamais d’écran de chargement figé',
      );
      expect(viewModel.needsOnboarding, isTrue);
      expect(viewModel.loadCommand.error, isTrue);
    },
  );

  test('l’écran de démarrage prévient une fois la lecture faite', () async {
    final viewModel = AppRootViewModel(
      profiles: FakeUserProfileRepository(name: 'Camille'),
    );
    var notified = 0;
    viewModel.addListener(() => notified++);

    await viewModel.loadCommand.execute();

    expect(notified, greaterThan(0));
  });
}
