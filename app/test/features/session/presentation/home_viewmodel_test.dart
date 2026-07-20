import 'package:flutter_test/flutter_test.dart';
import 'package:notalone/features/session/presentation/home_viewmodel.dart';

import '../../../helpers/fake_user_profile_repository.dart';

void main() {
  test('la home part du prénom que lui passe le démarrage', () {
    final viewModel = HomeViewModel(
      profiles: FakeUserProfileRepository(name: 'Camille'),
      name: 'Camille',
    );

    expect(viewModel.name, 'Camille');
  });

  test('prénom changé dans les réglages : la home le reprend', () async {
    final profiles = FakeUserProfileRepository(name: 'Camille');
    final viewModel = HomeViewModel(profiles: profiles, name: 'Camille');
    var notified = 0;
    viewModel.addListener(() => notified++);

    profiles.name = 'Paul';
    await viewModel.reloadCommand.execute();

    expect(viewModel.name, 'Paul');
    expect(notified, 1);
  });

  test('prénom inchangé : la home ne se reconstruit pas pour rien', () async {
    final profiles = FakeUserProfileRepository(name: 'Camille');
    final viewModel = HomeViewModel(profiles: profiles, name: 'Camille');
    var notified = 0;
    viewModel.addListener(() => notified++);

    await viewModel.reloadCommand.execute();

    expect(notified, 0);
  });

  test('relecture impossible : le prénom courant est conservé', () async {
    final profiles = FakeUserProfileRepository(name: 'Camille');
    final viewModel = HomeViewModel(profiles: profiles, name: 'Camille');

    profiles.name = null;
    await viewModel.reloadCommand.execute();

    expect(viewModel.name, 'Camille');
  });
}
