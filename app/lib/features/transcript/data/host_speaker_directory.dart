import 'dart:async';

import 'package:notalone/features/session/domain/host_server.dart';
import 'package:notalone/features/session/domain/participant.dart';
import 'package:notalone/features/transcript/domain/speaker.dart';
import 'package:notalone/features/transcript/domain/speaker_directory.dart';

/// Le registre du serveur hôte, vu par l'écran du fil : c'est ici, et nulle
/// part ailleurs, qu'un `Participant` de `session/` devient un [Speaker] de
/// `transcript/` (CLAUDE.md règle 3).
///
/// Comme le `HostTranscriptBinder`, il s'abonne au flux d'événements du serveur
/// plutôt que d'être notifié par le salon : les deux consommateurs du fil sont
/// alors indépendants l'un de l'autre, et aucun ne dépend de l'écran affiché.
class HostSpeakerDirectory implements SpeakerDirectory {
  HostSpeakerDirectory({required this._server}) {
    _speakers = _readServer();
    _events = _server.events.listen(_handleEvent);
  }

  final HostServer _server;

  late final StreamSubscription<HostServerEvent> _events;

  final StreamController<List<Speaker>> _changes =
      StreamController<List<Speaker>>.broadcast();

  late List<Speaker> _speakers;

  @override
  List<Speaker> get speakers => List.unmodifiable(_speakers);

  @override
  Stream<List<Speaker>> get changes => _changes.stream;

  @override
  Speaker? speakerOf(String participantId) =>
      _speakers.where((speaker) => speaker.id == participantId).firstOrNull;

  @override
  Future<void> dispose() async {
    await _events.cancel();
    await _changes.close();
  }

  void _handleEvent(HostServerEvent event) {
    switch (event) {
      case ParticipantJoined() || ParticipantDisconnected():
        // Un invité déconnecté reste dans l'annuaire : ses phrases sont déjà
        // au fil et doivent garder leur prénom et leur couleur.
        _speakers = _readServer();
        if (!_changes.isClosed) _changes.add(speakers);
      case ParticipantRejected() || SessionMessageReceived():
        return;
    }
  }

  List<Speaker> _readServer() => [
    for (final Participant participant in _server.participants)
      Speaker(
        id: participant.id,
        name: participant.name,
        colorIndex: participant.colorIndex,
      ),
  ];
}
