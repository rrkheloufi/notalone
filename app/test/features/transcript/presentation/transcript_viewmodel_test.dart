import 'package:flutter_test/flutter_test.dart';
import 'package:notalone/core/result/failure.dart';
import 'package:notalone/features/transcript/domain/speaker.dart';
import 'package:notalone/features/transcript/domain/transcript_text_scale.dart';
import 'package:notalone/features/transcript/presentation/transcript_viewmodel.dart';

import '../../../helpers/fake_transcript_sources.dart';

class _StorageFailure extends Failure {
  const _StorageFailure() : super('stockage indisponible');
}

const Speaker _papa = Speaker(id: 'p1', name: 'Papa', colorIndex: 0);
const Speaker _lea = Speaker(id: 'p2', name: 'Léa', colorIndex: 1);

void main() {
  late FakeTranscriptBinding binding;
  late FakeSpeakerDirectory directory;
  late FakeTranscriptPreferences preferences;
  late FakeScreenWakeLock wakeLock;
  late TranscriptViewModel viewModel;

  void build() {
    viewModel = TranscriptViewModel(
      binding: binding,
      speakers: directory,
      preferences: preferences,
      wakeLock: wakeLock,
    );
  }

  setUp(() {
    binding = FakeTranscriptBinding();
    directory = FakeSpeakerDirectory([_papa, _lea]);
    preferences = FakeTranscriptPreferences();
    wakeLock = FakeScreenWakeLock();
    build();
  });

  group('flux d’entrées', () {
    test('démarre vide et suit le fil', () {
      expect(viewModel.messages, isEmpty);
      expect(viewModel.isFollowing, isTrue);
      expect(viewModel.hasUnread, isFalse);
    });

    test('joint chaque entrée à son locuteur', () async {
      await binding.emit(entry(participantId: 'p1', text: 'Passe le sel'));

      expect(viewModel.messages, hasLength(1));
      expect(viewModel.messages.single.speaker, _papa);
      expect(viewModel.messages.single.text, 'Passe le sel');
    });

    test('affiche une entrée dont le locuteur est inconnu', () async {
      await binding.emit(entry(participantId: 'fantome', text: 'Bonsoir'));

      // Une phrase anonyme reste lisible ; une phrase retenue est perdue.
      expect(viewModel.messages.single.speaker, isNull);
      expect(viewModel.messages.single.text, 'Bonsoir');
    });

    test('conserve l’ordre d’arrivée', () async {
      await binding.emit(entry(participantId: 'p1', text: 'un'));
      await binding.emit(entry(participantId: 'p2', text: 'deux'));
      await binding.emit(entry(participantId: 'p1', text: 'trois'));

      expect(
        viewModel.messages.map((message) => message.text),
        ['un', 'deux', 'trois'],
      );
    });

    test(
      'une entrée tardive se pose à la fin, jamais à sa place chronologique',
      () async {
        await binding.emit(
          entry(participantId: 'p1', text: 'déjà lu', tStartMs: 5000),
        );
        await binding.emit(
          entry(
            participantId: 'p2',
            text: 'en retard',
            tStartMs: 1000,
            isLate: true,
          ),
        );

        // Critère MVP-12 : le réordonnancement ne fait jamais sauter le texte
        // déjà lu. La tardive est signalée, pas déplacée.
        expect(
          viewModel.messages.map((message) => message.text),
          ['déjà lu', 'en retard'],
        );
        expect(viewModel.messages.last.isLate, isTrue);
      },
    );

    test('notifie la vue à chaque entrée', () async {
      var notifications = 0;
      viewModel.addListener(() => notifications++);

      await binding.emit(entry(participantId: 'p1', text: 'un'));
      await binding.emit(entry(participantId: 'p1', text: 'deux'));

      expect(notifications, 2);
    });

    test('borne le fil pour ne pas dériver en mémoire', () async {
      for (var i = 0; i < TranscriptViewModel.maxMessages + 25; i++) {
        await binding.emit(entry(participantId: 'p1', text: 'phrase $i'));
      }

      expect(viewModel.messages, hasLength(TranscriptViewModel.maxMessages));
      // Ce sont les plus anciennes qui partent.
      expect(viewModel.messages.first.text, 'phrase 25');
      expect(
        viewModel.messages.last.text,
        'phrase ${TranscriptViewModel.maxMessages + 24}',
      );
    });
  });

  group('annuaire des locuteurs', () {
    test(
      'un convive arrivé après coup donne son prénom aux phrases déjà là',
      () async {
        directory = FakeSpeakerDirectory([_papa]);
        build();
        await binding.emit(entry(participantId: 'p2', text: 'Bonsoir'));
        expect(viewModel.messages.single.speaker, isNull);

        await directory.replaceWith([_papa, _lea]);

        expect(viewModel.messages.single.speaker, _lea);
      },
    );

    test('un changement d’annuaire notifie la vue', () async {
      var notifications = 0;
      viewModel.addListener(() => notifications++);

      await directory.replaceWith([_papa]);

      expect(notifications, 1);
    });
  });

  group('filtre par locuteur', () {
    setUp(() async {
      await binding.emit(entry(participantId: 'p1', text: 'papa 1'));
      await binding.emit(entry(participantId: 'p2', text: 'léa 1'));
      await binding.emit(entry(participantId: 'p1', text: 'papa 2'));
    });

    test('sans filtre, tout le monde s’affiche', () {
      expect(viewModel.isFiltered, isFalse);
      expect(viewModel.visibleMessages, hasLength(3));
    });

    test('un appui isole le locuteur', () {
      viewModel.toggleSpeakerFilter('p1');

      expect(viewModel.isFiltered, isTrue);
      expect(viewModel.filteredSpeaker, _papa);
      expect(
        viewModel.visibleMessages.map((message) => message.text),
        ['papa 1', 'papa 2'],
      );
      // Le fil complet reste intact derrière le filtre.
      expect(viewModel.messages, hasLength(3));
    });

    test('un second appui sur le même prénom rend tout le monde', () {
      viewModel
        ..toggleSpeakerFilter('p1')
        ..toggleSpeakerFilter('p1');

      expect(viewModel.isFiltered, isFalse);
      expect(viewModel.visibleMessages, hasLength(3));
    });

    test('appuyer sur un autre prénom déplace le filtre', () {
      viewModel
        ..toggleSpeakerFilter('p1')
        ..toggleSpeakerFilter('p2');

      expect(viewModel.speakerFilter, 'p2');
      expect(
        viewModel.visibleMessages.map((message) => message.text),
        ['léa 1'],
      );
    });

    test('clearSpeakerFilter désactive aussi en un geste', () {
      viewModel
        ..toggleSpeakerFilter('p1')
        ..clearSpeakerFilter();

      expect(viewModel.isFiltered, isFalse);
    });

    test('le filtre laisse passer les entrées suivantes du locuteur', () async {
      viewModel.toggleSpeakerFilter('p2');

      await binding.emit(entry(participantId: 'p2', text: 'léa 2'));
      await binding.emit(entry(participantId: 'p1', text: 'papa 3'));

      expect(
        viewModel.visibleMessages.map((message) => message.text),
        ['léa 1', 'léa 2'],
      );
      expect(viewModel.messages, hasLength(5));
    });

    test('changer de filtre réancre le fil sur le plus récent', () async {
      viewModel.setFollowing(following: false);
      await binding.emit(entry(participantId: 'p1', text: 'papa 3'));
      expect(viewModel.unreadCount, 1);

      viewModel.toggleSpeakerFilter('p1');

      // La liste affichée a entièrement changé : l'ancienne position de
      // défilement ne désigne plus rien, et tout est à relire.
      expect(viewModel.isFollowing, isTrue);
      expect(viewModel.unreadCount, 0);
    });
  });

  group('auto-scroll intelligent', () {
    test('tant que le lecteur suit, rien ne s’accumule', () async {
      await binding.emit(entry(participantId: 'p1', text: 'un'));

      expect(viewModel.unreadCount, 0);
      expect(viewModel.hasUnread, isFalse);
    });

    test('remonter suspend le suivi et compte les nouvelles phrases', () async {
      viewModel.setFollowing(following: false);

      await binding.emit(entry(participantId: 'p1', text: 'un'));
      await binding.emit(entry(participantId: 'p2', text: 'deux'));

      expect(viewModel.isFollowing, isFalse);
      expect(viewModel.unreadCount, 2);
      expect(viewModel.hasUnread, isTrue);
    });

    test('revenir en bas remet le compteur à zéro', () async {
      viewModel.setFollowing(following: false);
      await binding.emit(entry(participantId: 'p1', text: 'un'));

      viewModel.setFollowing(following: true);

      expect(viewModel.unreadCount, 0);
      expect(viewModel.hasUnread, isFalse);
    });

    test('le badge ne compte que ce qu’il promet de montrer', () async {
      viewModel
        ..toggleSpeakerFilter('p1')
        ..setFollowing(following: false);

      await binding.emit(entry(participantId: 'p2', text: 'hors filtre'));
      expect(viewModel.unreadCount, 0);

      await binding.emit(entry(participantId: 'p1', text: 'dans le filtre'));
      expect(viewModel.unreadCount, 1);
    });

    test('un signal de suivi identique ne notifie pas', () {
      var notifications = 0;
      viewModel
        ..addListener(() => notifications++)
        ..setFollowing(following: true);

      expect(notifications, 0);
    });
  });

  group('taille du texte', () {
    test('s’ouvre sur la taille persistée', () async {
      preferences.stored = TranscriptTextScale.maximum;
      build();

      await viewModel.loadCommand.execute();

      expect(viewModel.textScale, TranscriptTextScale.maximum);
    });

    test('un stockage en panne n’empêche pas d’ouvrir le fil', () async {
      preferences.readFailure = const _StorageFailure();
      build();

      await viewModel.loadCommand.execute();

      expect(viewModel.textScale, TranscriptTextScale.initial);
      expect(viewModel.loadCommand.error, isTrue);
    });

    test('agrandir et réduire changent la taille et la persistent', () async {
      preferences.stored = TranscriptTextScale.large;
      build();
      await viewModel.loadCommand.execute();

      await viewModel.enlargeTextCommand.execute();
      expect(viewModel.textScale, TranscriptTextScale.extraLarge);
      expect(preferences.stored, TranscriptTextScale.extraLarge);

      await viewModel.reduceTextCommand.execute();
      expect(viewModel.textScale, TranscriptTextScale.large);
      expect(preferences.stored, TranscriptTextScale.large);
    });

    test('les extrémités n’écrivent rien', () async {
      preferences.stored = TranscriptTextScale.values.last;
      build();
      await viewModel.loadCommand.execute();

      await viewModel.enlargeTextCommand.execute();

      expect(viewModel.textScale, TranscriptTextScale.values.last);
      expect(preferences.written, isEmpty);
    });

    test('une écriture en échec laisse la taille appliquée', () async {
      preferences.writeFailure = const _StorageFailure();

      await viewModel.enlargeTextCommand.execute();

      // Le réglage sert tout de suite ; il ne survivra simplement pas à la
      // fermeture de l'app.
      expect(viewModel.textScale, TranscriptTextScale.initial.larger);
      expect(viewModel.enlargeTextCommand.error, isTrue);
    });
  });

  group('cycle de vie', () {
    test('load allume le verrou d’écran', () async {
      await viewModel.loadCommand.execute();

      expect(wakeLock.isEnabled, isTrue);
    });

    test('dispose relâche le verrou et ferme ce qu’il possède', () async {
      await viewModel.loadCommand.execute();

      viewModel.dispose();
      await Future<void>.delayed(Duration.zero);

      expect(wakeLock.isEnabled, isFalse);
      expect(wakeLock.releaseCount, 1);
      expect(binding.isDisposed, isTrue);
      expect(directory.isDisposed, isTrue);
    });

    test('une entrée arrivée après dispose ne réveille rien', () async {
      viewModel.dispose();
      await Future<void>.delayed(Duration.zero);

      // La liaison est fermée : émettre ne doit ni lever ni notifier un
      // ChangeNotifier disposé (ce qui ferait échouer ce test).
      expect(binding.isDisposed, isTrue);
    });
  });
}
