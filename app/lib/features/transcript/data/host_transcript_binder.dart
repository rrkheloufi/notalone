import 'dart:async';

import 'package:notalone/features/session/domain/host_server.dart';
import 'package:notalone/features/session/domain/protocol/session_message.dart';
import 'package:notalone/features/transcript/domain/incoming_segment.dart';
import 'package:notalone/features/transcript/domain/merge_transcripts_use_case.dart';
import 'package:notalone/features/transcript/domain/transcript_binding.dart';
import 'package:notalone/features/transcript/domain/transcript_entry.dart';
import 'package:notalone/features/transcript/domain/transcript_timing_config.dart';

int _epochNowMs() => DateTime.now().millisecondsSinceEpoch;

/// Branche le serveur de session sur la fusion : c'est lui qui traduit le
/// protocole en entrées de domaine, et qui pilote la synchronisation d'horloge
/// (cf. cowork/02-architecture.md §4 et §5).
///
/// Trois responsabilités, et rien d'autre :
/// - **sonder les horloges** — à chaque admission, `clockProbeCount` échanges
///   `clock_sync` vers ce seul invité ;
/// - **mapper les réponses** vers `registerClockProbe` ;
/// - **mapper les `speech_segment`** vers la fusion.
///
/// La politique de sondage vit ici et pas dans le serveur : `HostServer` reste
/// un transport, et cette politique-là se teste sans ouvrir de socket. C'est
/// aussi pour cela que MVP-11 n'a pas eu à toucher `DartIoHostServer`.
class HostTranscriptBinder implements TranscriptBinding {
  HostTranscriptBinder({
    required this._server,
    required this._merge,
    this._timingConfig = const TranscriptTimingConfig(),
    this._probeSpacing = const Duration(milliseconds: 250),
    this._now = _epochNowMs,
    this._scheduleAfter = Timer.new,
  }) {
    _events = _server.events.listen(_handleEvent);
  }

  final HostServer _server;
  final MergeTranscriptsUseCase _merge;
  final TranscriptTimingConfig _timingConfig;

  /// Les sondes sont espacées plutôt qu'envoyées en rafale : cinq mesures
  /// prises dans la même milliseconde subiraient toutes le même aléa de Wi-Fi,
  /// et leur médiane ne vaudrait pas mieux qu'une seule (doc 02 §4).
  final Duration _probeSpacing;

  final int Function() _now;
  final TimerFactory _scheduleAfter;

  late final StreamSubscription<HostServerEvent> _events;

  /// Une séquence de sondes en cours par invité, remplacée s'il se reconnecte.
  final Map<String, Timer> _probeTimers = {};

  final Map<String, int> _probeSeq = {};

  bool _disposed = false;

  @override
  Stream<TranscriptEntry> get entries => _merge.entries;

  MergeTranscriptsUseCase get merge => _merge;

  @override
  Future<void> dispose() async {
    _disposed = true;
    for (final timer in _probeTimers.values) {
      timer.cancel();
    }
    _probeTimers.clear();
    await _events.cancel();
    await _merge.dispose();
  }

  void _handleEvent(HostServerEvent event) {
    if (_disposed) return;
    switch (event) {
      case ParticipantJoined(:final participant):
        // Une reconnexion est resondée comme une première entrée : le
        // téléphone a pu remettre son horloge à l'heure entre-temps, et la
        // fenêtre glissante de `SyncedClock` chassera les vieilles mesures.
        _probeParticipant(participant.id);
      case SessionMessageReceived(:final participantId, :final message):
        _handleMessage(participantId, message);
      case ParticipantDisconnected() || ParticipantRejected():
        // L'offset d'un invité parti lui reste réservé, comme sa couleur : il
        // reviendra probablement avec la même horloge.
        return;
    }
  }

  void _handleMessage(String participantId, SessionMessage message) {
    switch (message) {
      case ClockSync(
        :final tHostSentMs,
        :final tGuestReceivedMs,
        :final tGuestSentMs,
      ):
        if (tGuestReceivedMs == null || tGuestSentMs == null) return;
        // t3 est pris ici, au plus près de la réception. Une sonde aberrante
        // est refusée par `SyncedClock` plutôt que d'entrer dans la médiane.
        _merge.registerClockProbe(
          participantId: participantId,
          hostSentMs: tHostSentMs,
          guestReceivedMs: tGuestReceivedMs,
          guestSentMs: tGuestSentMs,
          hostReceivedMs: _now(),
        );
      case SpeechSegmentDto(
        :final segmentId,
        :final tStartMs,
        :final tEndMs,
        :final text,
        :final isFinal,
        :final energyDb,
        :final engine,
      ):
        _merge.submit(
          IncomingSegment(
            participantId: participantId,
            segmentId: segmentId,
            tStartMs: tStartMs,
            tEndMs: tEndMs,
            text: text,
            energyDb: energyDb,
            engine: engine,
            isFinal: isFinal,
          ),
        );
      case JoinAck() || JoinRequest() || MicStatus() || SessionEnd() ||
          Ping() || Pong():
        // `mic_status` est la supervision (MVP-13), le reste appartient au
        // serveur : rien de tout cela ne concerne le fil.
        return;
    }
  }

  void _probeParticipant(String participantId) {
    _probeTimers.remove(participantId)?.cancel();
    _sendProbes(participantId, _timingConfig.clockProbeCount);
  }

  void _sendProbes(String participantId, int remaining) {
    if (_disposed || remaining <= 0) return;
    final seq = _probeSeq.update(
      participantId,
      (previous) => previous + 1,
      ifAbsent: () => 0,
    );
    _server.sendTo(
      participantId,
      ClockSync(seq: seq, tHostSentMs: _now()),
    );
    if (remaining == 1) return;
    _probeTimers[participantId] = _scheduleAfter(_probeSpacing, () {
      _probeTimers.remove(participantId);
      _sendProbes(participantId, remaining - 1);
    });
  }
}
