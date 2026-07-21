import 'dart:async';

import 'package:notalone/core/result/result.dart';
import 'package:notalone/features/transcript/domain/clock_probe.dart';
import 'package:notalone/features/transcript/domain/dedup_config.dart';
import 'package:notalone/features/transcript/domain/incoming_segment.dart';
import 'package:notalone/features/transcript/domain/reorder_buffer.dart';
import 'package:notalone/features/transcript/domain/segment_overlap.dart';
import 'package:notalone/features/transcript/domain/synced_clock.dart';
import 'package:notalone/features/transcript/domain/text_normalizer.dart';
import 'package:notalone/features/transcript/domain/text_similarity.dart';
import 'package:notalone/features/transcript/domain/transcript_entry.dart';
import 'package:notalone/features/transcript/domain/transcript_timing_config.dart';

/// Fabrique de minuteur, injectée pour que les tests pilotent le temps sans
/// attendre réellement.
typedef TimerFactory =
    Timer Function(Duration duration, void Function() callback);

int _epochNowMs() => DateTime.now().millisecondsSinceEpoch;

/// La fusion côté hôte, cœur du produit (cf. cowork/02-architecture.md §5).
///
/// Chaque segment traverse trois étages, dans cet ordre :
/// 1. **normalisation temporelle** — l'horodatage de l'émetteur est ramené sur
///    l'horloge de l'hôte via [SyncedClock] ;
/// 2. **déduplication cross-talk** — le segment est confronté à ceux qui
///    attendent encore dans la fenêtre : même énoncé capté par deux micros
///    (chevauchement × similarité de texte) ⇒ le plus énergique gagne et
///    absorbe l'autre ;
/// 3. **réordonnancement** — [ReorderBuffer] retient l'entrée le temps qu'un
///    segment parti plus tôt d'un autre téléphone puisse la rattraper.
///
/// La déduplication passe **avant** le figeage, à dessein : une fois l'entrée
/// sortie, le doc 02 §5.2 interdit d'y toucher. Un jumeau arrivé après coup est
/// donc écarté même s'il était plus énergique — mieux vaut la mauvaise
/// attribution que du texte qui se réorganise sous les yeux du lecteur.
///
/// Pur Dart : ni transport, ni horloge système imposée, tout est rejouable.
class MergeTranscriptsUseCase {
  MergeTranscriptsUseCase({
    SyncedClock? clock,
    this._dedupConfig = const DedupConfig(),
    TranscriptTimingConfig timingConfig = const TranscriptTimingConfig(),
    this._now = _epochNowMs,
    this._scheduleAfter = Timer.new,
  }) : _clock = clock ?? SyncedClock(config: timingConfig) {
    _buffer = ReorderBuffer<_Candidate>(
      timestampOf: (candidate) => candidate.tStartMs,
      config: timingConfig,
    );
  }

  final DedupConfig _dedupConfig;
  final SyncedClock _clock;
  final int Function() _now;
  final TimerFactory _scheduleAfter;

  late final ReorderBuffer<_Candidate> _buffer;

  final StreamController<TranscriptEntry> _entries =
      StreamController<TranscriptEntry>.broadcast();

  /// Entrées déjà figées, gardées le temps de [DedupConfig.lateDuplicateWindow]
  /// pour reconnaître un jumeau qui arriverait après elles. Purgée à chaque
  /// sortie : c'est ce qui borne la mémoire sur un repas de 2 h.
  final List<_Candidate> _released = [];

  Timer? _releaseTimer;
  bool _disposed = false;

  /// Le fil fusionné, dans l'ordre où le lecteur doit le voir.
  Stream<TranscriptEntry> get entries => _entries.stream;

  /// Segments écartés parce qu'un autre micro avait mieux capté le même
  /// énoncé. Avec [lateDuplicates], c'est la mesure du « taux de doublons »
  /// des critères MVP-11 et MVP-15.
  int _deduplicatedSegments = 0;
  int get deduplicatedSegments => _deduplicatedSegments;

  /// Doublons arrivés trop tard pour arbitrer : leur jumeau était déjà figé.
  int _lateDuplicates = 0;
  int get lateDuplicates => _lateDuplicates;

  /// Partiels reçus, donc écartés (doc 02 §5.4). Reste à zéro tant qu'aucun
  /// moteur n'en produit ; un compteur qui bouge en MVP-14 dira que la
  /// question du rendu des partiels est devenue réelle.
  int _discardedPartials = 0;
  int get discardedPartials => _discardedPartials;

  int get pendingEntries => _buffer.pending;

  /// Entrées figées encore gardées pour reconnaître un doublon tardif. Avec
  /// [pendingEntries], c'est toute la mémoire que la fusion accumule : les
  /// deux doivent rester bornées sur un repas de 2 h (critère MVP-11).
  int get retainedForDedup => _released.length;

  /// Enregistre un aller-retour `clock_sync` (doc 02 §4). Les quatre
  /// horodatages sont des nombres bruts : le mapping depuis le DTO appartient
  /// à `transcript/data/`.
  Result<ClockOffset> registerClockProbe({
    required String participantId,
    required int hostSentMs,
    required int guestReceivedMs,
    required int guestSentMs,
    required int hostReceivedMs,
  }) => _clock.registerProbe(
    participantId: participantId,
    hostSentMs: hostSentMs,
    guestReceivedMs: guestReceivedMs,
    guestSentMs: guestSentMs,
    hostReceivedMs: hostReceivedMs,
  );

  bool isSynced(String participantId) => _clock.isSynced(participantId);

  ClockOffset? offsetFor(String participantId) =>
      _clock.offsetFor(participantId);

  /// Soumet un segment. Ne rend rien : l'entrée qui en sortira — ou pas, si
  /// elle est reconnue comme un doublon — arrivera par [entries].
  void submit(IncomingSegment segment) {
    if (_disposed) return;
    if (!segment.isFinal) {
      _discardedPartials++;
      return;
    }
    final candidate = _Candidate(
      segmentId: segment.segmentId,
      participantId: segment.participantId,
      text: segment.text,
      normalizedText: normalizeForComparison(segment.text),
      tStartMs: _clock.toHostTimeMs(
        participantId: segment.participantId,
        guestTimeMs: segment.tStartMs,
      ),
      tEndMs: _clock.toHostTimeMs(
        participantId: segment.participantId,
        guestTimeMs: segment.tEndMs,
      ),
      energyDb: segment.energyDb,
      engine: segment.engine,
    );
    if (_isLateDuplicate(candidate)) {
      _lateDuplicates++;
      _deduplicatedSegments++;
      return;
    }
    if (_arbitrateAgainstPending(candidate)) {
      _buffer.add(candidate);
      _scheduleRelease();
    }
  }

  /// Rend les entrées mûres à l'instant [nowMs]. Public et déterministe : les
  /// tests pilotent le temps, et l'appelant peut forcer un tour de fil.
  List<TranscriptEntry> release(int nowMs) =>
      _emit(_buffer.release(nowMs), nowMs);

  /// Vide le fil sans attendre (fin de session, MVP-13) : il ne reste rien à
  /// rattraper et le lecteur doit voir les dernières phrases.
  List<TranscriptEntry> flush() => _emit(_buffer.flush(), _now());

  /// Oublie un participant : son offset d'horloge et les entrées figées qui le
  /// concernent ne serviront plus à dédupliquer quoi que ce soit.
  void forget(String participantId) {
    _clock.forget(participantId);
    _released.removeWhere(
      (candidate) => candidate.participantId == participantId,
    );
  }

  Future<void> dispose() async {
    _disposed = true;
    _releaseTimer?.cancel();
    _releaseTimer = null;
    _released.clear();
    _clock.clear();
    await _entries.close();
  }

  /// Confronte [candidate] à tout ce qui attend encore. Rend `false` quand il
  /// a perdu et n'a donc pas à entrer dans le buffer.
  ///
  /// Trois micros peuvent avoir capté le même énoncé : on ne s'arrête pas au
  /// premier rival, le vainqueur courant absorbe chacun des suivants.
  bool _arbitrateAgainstPending(_Candidate candidate) {
    final rivals = [
      for (final pending in _buffer.pendingEntries)
        if (_isSameUtterance(candidate, pending)) pending,
    ];
    var winner = candidate;
    for (final rival in rivals) {
      final rivalWins = rival.energyDb > winner.energyDb;
      final loser = rivalWins ? winner : rival;
      // Le perdant n'est dans le buffer que s'il y était déjà : le candidat,
      // lui, n'y entrera jamais. À énergie égale, le premier arrivé reste.
      _buffer.remove(loser);
      _deduplicatedSegments++;
      if (rivalWins) winner = rival;
      winner.absorb(loser);
    }
    return identical(winner, candidate);
  }

  /// Le jumeau est déjà figé : le candidat est écarté sans discussion, même
  /// s'il était le plus énergique. Rien ne se rétracte une fois affiché
  /// (doc 02 §5.2).
  bool _isLateDuplicate(_Candidate candidate) =>
      _released.any((released) => _isSameUtterance(candidate, released));

  /// Deux segments décrivent le même énoncé s'ils viennent de **deux micros
  /// différents**, se chevauchent assez, et disent la même chose.
  ///
  /// La condition sur le participant n'est pas un détail : deux segments
  /// successifs d'une même personne peuvent parfaitement se ressembler
  /// (« oui, oui »), les fusionner effacerait une vraie phrase. Le cross-talk,
  /// par définition, est un énoncé capté par plusieurs téléphones.
  bool _isSameUtterance(_Candidate a, _Candidate b) {
    if (a.participantId == b.participantId) return false;
    if (a.normalizedText.isEmpty || b.normalizedText.isEmpty) return false;
    final iou = temporalIou(
      aStartMs: a.tStartMs,
      aEndMs: a.tEndMs,
      bStartMs: b.tStartMs,
      bEndMs: b.tEndMs,
    );
    if (iou < _dedupConfig.minOverlapIou) return false;
    return isSimilarAtLeast(
      a.normalizedText,
      b.normalizedText,
      _dedupConfig.minTextSimilarity,
    );
  }

  List<TranscriptEntry> _emit(
    List<ReorderedEntry<_Candidate>> released,
    int nowMs,
  ) {
    final entries = <TranscriptEntry>[];
    for (final reordered in released) {
      final entry = reordered.value.toEntry(isLate: reordered.isLate);
      entries.add(entry);
      _released.add(reordered.value);
      if (!_entries.isClosed) _entries.add(entry);
    }
    _pruneReleased(nowMs);
    _scheduleRelease();
    return entries;
  }

  /// Purge les entrées figées sorties de la fenêtre aux doublons tardifs.
  /// Appuyée sur l'horodatage des entrées et non sur leur nombre : c'est la
  /// borne qui tient quel que soit le débit de parole.
  void _pruneReleased(int nowMs) {
    final horizon = nowMs - _dedupConfig.lateDuplicateWindowMs;
    _released.removeWhere((candidate) => candidate.tEndMs < horizon);
  }

  /// Programme le prochain tour de fil sur l'échéance que le buffer annonce,
  /// plutôt que d'interroger celui-ci en boucle (`nextDueMs`, MVP-09).
  void _scheduleRelease() {
    _releaseTimer?.cancel();
    _releaseTimer = null;
    if (_disposed) return;
    final dueMs = _buffer.nextDueMs;
    if (dueMs == null) return;
    final delayMs = dueMs - _now();
    _releaseTimer = _scheduleAfter(
      Duration(milliseconds: delayMs < 0 ? 0 : delayMs),
      () {
        _releaseTimer = null;
        release(_now());
      },
    );
  }
}

/// Un segment en cours d'arbitrage : ses horodatages sont déjà sur l'horloge
/// hôte, son texte déjà nettoyé. Mutable par ses seuls [absorb] : un segment
/// qui gagne accumule les identifiants de ceux qu'il a écartés.
class _Candidate {
  _Candidate({
    required this.segmentId,
    required this.participantId,
    required this.text,
    required this.normalizedText,
    required this.tStartMs,
    required this.tEndMs,
    required this.energyDb,
    required this.engine,
  });

  final String segmentId;
  final String participantId;
  final String text;
  final String normalizedText;
  final int tStartMs;
  final int tEndMs;
  final double energyDb;
  final String engine;

  final List<String> _merged = [];

  /// Reprend le segment écarté **et ceux qu'il avait lui-même absorbés** :
  /// sur trois micros, le dernier vainqueur doit porter la trace des deux
  /// autres.
  void absorb(_Candidate loser) {
    _merged
      ..add(loser.segmentId)
      ..addAll(loser._merged);
  }

  TranscriptEntry toEntry({required bool isLate}) => TranscriptEntry(
    segmentId: segmentId,
    participantId: participantId,
    text: text,
    tStartMs: tStartMs,
    tEndMs: tEndMs,
    energyDb: energyDb,
    engine: engine,
    isLate: isLate,
    mergedSegmentIds: List.unmodifiable(_merged),
  );
}
