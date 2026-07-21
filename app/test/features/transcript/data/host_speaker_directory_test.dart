import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:notalone/core/result/result.dart';
import 'package:notalone/features/session/domain/host_server.dart';
import 'package:notalone/features/session/domain/participant.dart';
import 'package:notalone/features/session/domain/protocol/session_message.dart';
import 'package:notalone/features/transcript/data/host_speaker_directory.dart';
import 'package:notalone/features/transcript/domain/speaker.dart';

/// Serveur réduit à ce dont l'annuaire dépend : un registre et un flux
/// d'événements que le test pilote.
class _FakeHostServer implements HostServer {
  _FakeHostServer([List<Participant> initial = const []])
    : _participants = [...initial];

  List<Participant> _participants;

  final StreamController<HostServerEvent> _events =
      StreamController<HostServerEvent>.broadcast();

  @override
  Stream<HostServerEvent> get events => _events.stream;

  @override
  List<Participant> get participants => List.unmodifiable(_participants);

  Future<void> emitJoin(Participant participant) async {
    _participants = [..._participants, participant];
    _events.add(
      ParticipantJoined(participant: participant, isReconnection: false),
    );
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> emitDisconnect(Participant participant) async {
    _participants = [
      for (final known in _participants)
        if (known.id == participant.id)
          known.copyWith(isConnected: false)
        else
          known,
    ];
    _events.add(ParticipantDisconnected(participant));
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> emitRejection() async {
    _events.add(
      const ParticipantRejected(reason: 'session pleine', closeCode: 4001),
    );
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> emitMessage(SessionMessage message) async {
    _events.add(
      SessionMessageReceived(participantId: 'p1', message: message),
    );
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> close() => _events.close();

  @override
  void broadcast(SessionMessage message) {}

  @override
  void sendTo(String participantId, SessionMessage message) {}

  @override
  Future<void> endSession() async {}

  @override
  Future<Result<HostServerInfo>> start({required String hostName}) =>
      throw UnimplementedError();
}

Participant _participant(String id, String name, int colorIndex) => Participant(
  id: id,
  name: name,
  colorIndex: colorIndex,
  isHost: false,
  isConnected: true,
);

void main() {
  late _FakeHostServer server;
  late HostSpeakerDirectory directory;

  setUp(() {
    server = _FakeHostServer([_participant('h', 'Rayan', 0)]);
    directory = HostSpeakerDirectory(server: server);
  });

  tearDown(() async {
    await directory.dispose();
    await server.close();
  });

  test('reprend le registre déjà en place à la construction', () {
    expect(
      directory.speakers,
      const [Speaker(id: 'h', name: 'Rayan', colorIndex: 0)],
    );
  });

  test('traduit chaque participant en locuteur, prénom et couleur', () async {
    await server.emitJoin(_participant('p1', 'Papa', 3));

    expect(directory.speakerOf('p1'), const Speaker(
      id: 'p1',
      name: 'Papa',
      colorIndex: 3,
    ));
  });

  test('annonce chaque admission', () async {
    final seen = <List<Speaker>>[];
    final subscription = directory.changes.listen(seen.add);

    await server.emitJoin(_participant('p1', 'Papa', 1));
    await server.emitJoin(_participant('p2', 'Léa', 2));

    expect(seen, hasLength(2));
    expect(seen.last.map((speaker) => speaker.name), ['Rayan', 'Papa', 'Léa']);
    await subscription.cancel();
  });

  test('un invité déconnecté reste dans l’annuaire', () async {
    final papa = _participant('p1', 'Papa', 1);
    await server.emitJoin(papa);

    await server.emitDisconnect(papa);

    // Ses phrases sont déjà au fil : elles doivent garder prénom et couleur.
    expect(directory.speakerOf('p1')?.name, 'Papa');
    expect(directory.speakerOf('p1')?.colorIndex, 1);
  });

  test('ignore ce qui ne concerne pas l’identité des convives', () async {
    final seen = <List<Speaker>>[];
    final subscription = directory.changes.listen(seen.add);

    await server.emitRejection();
    await server.emitMessage(const Ping(seq: 1));

    expect(seen, isEmpty);
    await subscription.cancel();
  });

  test('un identifiant inconnu ne rend pas de locuteur', () {
    expect(directory.speakerOf('jamais-vu'), isNull);
  });

  test('la liste exposée n’est pas modifiable', () {
    expect(
      () => directory.speakers.add(
        const Speaker(id: 'x', name: 'X', colorIndex: 0),
      ),
      throwsUnsupportedError,
    );
  });

  test('dispose se détache du serveur', () async {
    await directory.dispose();

    await server.emitJoin(_participant('p1', 'Papa', 1));

    expect(directory.speakerOf('p1'), isNull);
  });
}
