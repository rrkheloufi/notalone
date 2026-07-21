import 'package:flutter_test/flutter_test.dart';
import 'package:notalone/features/onboarding/domain/onboarding_failure.dart';
import 'package:notalone/features/settings/presentation/settings_viewmodel.dart';
import 'package:notalone/features/transcript/domain/transcript_failure.dart';
import 'package:notalone/features/transcript/domain/transcript_text_scale.dart';

import '../../../helpers/fake_transcript_sources.dart';
import '../../../helpers/fake_user_profile_repository.dart';

void main() {
  test('les réglages ouvrent sur le prénom courant', () async {
    final viewModel = SettingsViewModel(
      profiles: FakeUserProfileRepository(name: 'Camille'),
      preferences: FakeTranscriptPreferences(),
    );

    await viewModel.loadCommand.execute();

    expect(viewModel.name, 'Camille');
  });

  test('le nouveau prénom est persisté', () async {
    final profiles = FakeUserProfileRepository(name: 'Camille');
    final viewModel = SettingsViewModel(
      profiles: profiles,
      preferences: FakeTranscriptPreferences(),
    );

    await viewModel.saveCommand.execute('  Paul ');

    expect(profiles.written, ['Paul']);
    expect(viewModel.name, 'Paul');
  });

  test('un prénom vide ne remplace pas l’ancien', () async {
    final profiles = FakeUserProfileRepository(name: 'Camille');
    final viewModel = SettingsViewModel(
      profiles: profiles,
      preferences: FakeTranscriptPreferences(),
    );

    await viewModel.saveCommand.execute('  ');

    expect(profiles.written, isEmpty);
    expect(profiles.name, 'Camille');
  });

  test('écriture impossible : la commande signale l’échec', () async {
    final profiles = FakeUserProfileRepository(name: 'Camille')
      ..writeFailure = const ProfileStorageFailure('disque plein');
    final viewModel = SettingsViewModel(
      profiles: profiles,
      preferences: FakeTranscriptPreferences(),
    );

    await viewModel.saveCommand.execute('Paul');

    expect(viewModel.saveCommand.error, isTrue);
    expect(viewModel.name, isNot('Paul'));
  });

  group('taille du texte (MVP-13)', () {
    test('les réglages ouvrent sur la taille persistée', () async {
      final preferences = FakeTranscriptPreferences(
        stored: TranscriptTextScale.maximum,
      );
      final viewModel = SettingsViewModel(
        profiles: FakeUserProfileRepository(name: 'Camille'),
        preferences: preferences,
      );

      await viewModel.loadCommand.execute();

      expect(viewModel.textScale, TranscriptTextScale.maximum);
    });

    test('la nouvelle taille est persistée', () async {
      final preferences = FakeTranscriptPreferences();
      final viewModel = SettingsViewModel(
        profiles: FakeUserProfileRepository(name: 'Camille'),
        preferences: preferences,
      );

      await viewModel.textScaleCommand.execute(TranscriptTextScale.maximum);

      expect(viewModel.textScale, TranscriptTextScale.maximum);
      expect(preferences.written, [TranscriptTextScale.maximum]);
    });

    test('c’est le même réglage que celui du fil', () async {
      // Un seul repository pour les deux écrans : régler ici puis ouvrir le
      // fil, ou l'inverse, donne le même résultat (MVP-12 l'avait prévu).
      final preferences = FakeTranscriptPreferences();
      final viewModel = SettingsViewModel(
        profiles: FakeUserProfileRepository(name: 'Camille'),
        preferences: preferences,
      );

      await viewModel.textScaleCommand.execute(TranscriptTextScale.large);

      expect(
        (await preferences.readTextScale()).valueOrNull,
        TranscriptTextScale.large,
      );
    });

    test('la même taille rejouée n’écrit rien', () async {
      final preferences = FakeTranscriptPreferences();
      final viewModel = SettingsViewModel(
        profiles: FakeUserProfileRepository(name: 'Camille'),
        preferences: preferences,
      );
      await viewModel.loadCommand.execute();

      await viewModel.textScaleCommand.execute(viewModel.textScale);

      expect(preferences.written, isEmpty);
    });

    test('préférence illisible : le prénom reste accessible', () async {
      // Les deux lectures sont indépendantes : l'une en panne ne prive pas
      // l'utilisateur de l'autre.
      final preferences = FakeTranscriptPreferences(
        readFailure: const TranscriptPreferencesFailure('stockage illisible'),
      );
      final viewModel = SettingsViewModel(
        profiles: FakeUserProfileRepository(name: 'Camille'),
        preferences: preferences,
      );

      await viewModel.loadCommand.execute();

      expect(viewModel.name, 'Camille');
      expect(viewModel.textScale, TranscriptTextScale.initial);
    });
  });
}
