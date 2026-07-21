import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:notalone/core/result/result.dart';
import 'package:notalone/features/session/domain/host_server.dart';
import 'package:notalone/features/session/domain/participant.dart';
import 'package:notalone/features/session/domain/protocol/session_message.dart';
import 'package:notalone/features/transcript/data/host_transcript_binder.dart';
import 'package:notalone/features/transcript/domain/merge_transcripts_use_case.dart';
import 'package:notalone/features/transcript/domain/transcript_entry.dart';
import 'package:notalone/features/transcript/domain/transcript_timing_config.dart';

const _guest = Participant(
  id: 'g1',
  name: 'Camille',
  colorIndex: 1,
  isHost: false,
  isConnected: true,
);

const _other = Participant(
  id: 'g2',
  name: 'Luc',
  colorIndex: 2,
  isHost: false,
  isConnected: true,
);

final class _FakeHostServer implements HostServer {
  final StreamController<HostServerEvent> _events =
      StreamController.broadcast();

  final List<({String participantId, SessionMessage message})> sent = [];

  List<ClockSync> clockSyncsTo(String participantId) => [
    for (final entry in sent)
      if (entry.participantId == participantId &&
          entry.message is ClockSync)
        entry.message as ClockSync,
  ];

  @override
  List<Participant> participants = const [];

  @override
  Stream<HostServerEvent> get events => _events.stream;

  @override
  Future<Result<HostServerInfo>> start({required String hostName}) async =>
      throw UnimplementedError();

  @override
  void broadcast(SessionMessage message) {}

  @override
  void sendTo(String participantId, SessionMessage message) =>
      sent.add((participantId: participantId, message: message));

  @override
  Future<void> endSession() async {}

  Future<void> emit(HostServerEvent event) async {
    _events.add(event);
    await Future<void>.delayed(Duration.zero);
  }
}

/// Minuteur piloté par le test : `fire()` déclenche l'échéance en attente.
class _ManualTimers {
  final List<void Function()> _pending = [];

  Timer create(Duration duration, void Function() callback) {
    _pending.add(callback);
    return Timer(const Duration(days: 1), () {});
  }

  bool get hasPending => _pending.isNotEmpty;

  void fireAll() {
    // Chaque échéance en reprogramme une : on déroule jusqu'à épuisement.
    var guard = 0;
    while (_pending.isNotEmpty && guard++ < 100) {
      _pending.removeAt(0)();
    }
  }
}

void main() {
  late _FakeHostServer server;
  late _ManualTimers timers;
  late MergeTranscriptsUseCase merge;
  late HostTranscriptBinder binder;
  late int nowMs;

  setUp(() {
    server = _FakeHostServer();
    timers = _ManualTimers();
    nowMs = 100000;
    merge = MergeTranscriptsUseCase(
      now: () => nowMs,
      scheduleAfter: (duration, callback) =>
          Timer(const Duration(days: 1), callback),
    );
    binder = HostTranscriptBinder(
      server: server,
      merge: merge,
      now: () => nowMs,
      scheduleAfter: timers.create,
    );
  });

  tearDown(() => binder.dispose());

  group("synchronisation d'horloge", () {
    test('une admission déclenche la série complète de sondes', () async {
      await server.emit(
        const ParticipantJoined(participant: _guest, isReconnection: false),
      );
      timers.fireAll();

      final expected = const TranscriptTimingConfig().clockProbeCount;
      final probes = server.clockSyncsTo('g1');
      expect(probes, hasLength(expected));
      // Séquences distinctes : c'est ce qui apparie chaque réponse à sa sonde.
      expect(probes.map((probe) => probe.seq).toSet(), hasLength(expected));
      expect(probes.every((probe) => probe.isReply), isFalse);
    });

    test('les sondes ne partent pas dans la même milliseconde', () async {
      await server.emit(
        const ParticipantJoined(participant: _guest, isReconnection: false),
      );

      // Une seule sonde tant que les échéances n'ont pas couru : les quatre
      // suivantes sont espacées (sinon la médiane ne vaudrait pas mieux qu'une
      // mesure unique).
      expect(server.clockSyncsTo('g1'), hasLength(1));
      expect(timers.hasPending, isTrue);
    });

    test('chaque invité est sondé pour lui-même', () async {
      await server.emit(
        const ParticipantJoined(participant: _guest, isReconnection: false),
      );
      await server.emit(
        const ParticipantJoined(participant: _other, isReconnection: false),
      );
      timers.fireAll();

      expect(server.clockSyncsTo('g1'), isNotEmpty);
      expect(server.clockSyncsTo('g2'), isNotEmpty);
    });

    test('une reconnexion relance une série neuve', () async {
      await server.emit(
        const ParticipantJoined(participant: _guest, isReconnection: false),
      );
      timers.fireAll();
      final firstRound = server.clockSyncsTo('g1').length;

      await server.emit(
        const ParticipantJoined(participant: _guest, isReconnection: true),
      );
      timers.fireAll();

      expect(server.clockSyncsTo('g1').length, firstRound * 2);
    });

    test('une réponse alimente SyncedClock, t3 pris à la réception', () async {
      // L'invité avance de 2 s : t0=1000, t1=3010, t2=3011, t3=1021.
      nowMs = 1021;
      await server.emit(
        const SessionMessageReceived(
          participantId: 'g1',
          message: ClockSync(
            seq: 0,
            tHostSentMs: 1000,
            tGuestReceivedMs: 3010,
            tGuestSentMs: 3011,
          ),
        ),
      );

      expect(merge.offsetFor('g1')!.offsetMs, closeTo(2000, 20));
    });

    test('une sonde non répondue est ignorée', () async {
      await server.emit(
        const SessionMessageReceived(
          participantId: 'g1',
          message: ClockSync(seq: 0, tHostSentMs: 1000),
        ),
      );

      expect(merge.offsetFor('g1'), isNull);
    });
  });

  group('segments', () {
    test('un speech_segment entre dans la fusion, attribué à son émetteur',
        () async {
      await server.emit(
        const SessionMessageReceived(
          participantId: 'g1',
          message: SpeechSegmentDto(
            segmentId: 's1',
            tStartMs: 50000,
            tEndMs: 52000,
            text: 'Tu peux me passer le sel',
            isFinal: true,
            energyDb: -8,
            engine: 'ios_speech_analyzer',
          ),
        ),
      );

      final released = merge.release(60000);
      expect(released, hasLength(1));
      expect(released.single.participantId, 'g1');
      expect(released.single.text, 'Tu peux me passer le sel');
      expect(released.single.engine, 'ios_speech_analyzer');
    });

    test('deux invités sur la même phrase : une seule entrée en sortie',
        () async {
      await server.emit(
        const SessionMessageReceived(
          participantId: 'g1',
          message: SpeechSegmentDto(
            segmentId: 'proche',
            tStartMs: 50000,
            tEndMs: 52400,
            text: 'Tu peux me passer le sel',
            isFinal: true,
            energyDb: -8,
            engine: 'ios_speech_analyzer',
          ),
        ),
      );
      await server.emit(
        const SessionMessageReceived(
          participantId: 'g2',
          message: SpeechSegmentDto(
            segmentId: 'lointain',
            tStartMs: 50180,
            tEndMs: 52180,
            text: 'tu peux me passer le seul',
            isFinal: true,
            energyDb: -32,
            engine: 'android_on_device',
          ),
        ),
      );

      final released = merge.release(54000);
      expect(released, hasLength(1));
      expect(released.single.participantId, 'g1');
    });

    test('les messages qui ne concernent pas le fil sont ignorés', () async {
      await server.emit(
        const SessionMessageReceived(
          participantId: 'g1',
          message: MicStatus(state: MicStatusState.muted, batteryPct: 40),
        ),
      );
      await server.emit(const ParticipantDisconnected(_guest));
      await server.emit(
        const ParticipantRejected(reason: 'token invalide', closeCode: 4001),
      );

      expect(merge.pendingEntries, 0);
      expect(server.sent, isEmpty);
    });
  });

  group('cycle de vie', () {
    test('le fil du binder est celui de la fusion', () async {
      final seen = <TranscriptEntry>[];
      final subscription = binder.entries.listen(seen.add);
      addTearDown(subscription.cancel);

      await server.emit(
        const SessionMessageReceived(
          participantId: 'g1',
          message: SpeechSegmentDto(
            segmentId: 's1',
            tStartMs: 50000,
            tEndMs: 51000,
            text: 'Bonsoir',
            isFinal: true,
            energyDb: -8,
            engine: 'ios_speech_analyzer',
          ),
        ),
      );
      merge.release(60000);
      await Future<void>.delayed(Duration.zero);

      expect(seen.single.text, 'Bonsoir');
    });

    test('dispose coupe les sondes en cours et ferme la fusion', () async {
      await server.emit(
        const ParticipantJoined(participant: _guest, isReconnection: false),
      );
      final beforeDispose = server.clockSyncsTo('g1').length;

      await binder.dispose();
      timers.fireAll();

      expect(server.clockSyncsTo('g1'), hasLength(beforeDispose));
      // La fusion est fermée : plus rien n'entre.
      await server.emit(
        const SessionMessageReceived(
          participantId: 'g1',
          message: SpeechSegmentDto(
            segmentId: 's1',
            tStartMs: 50000,
            tEndMs: 51000,
            text: 'Trop tard',
            isFinal: true,
            energyDb: -8,
            engine: 'ios_speech_analyzer',
          ),
        ),
      );
      expect(merge.pendingEntries, 0);
    });
  });
}
