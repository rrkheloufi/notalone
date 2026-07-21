import 'dart:async';

import 'package:notalone/core/result/failure.dart';
import 'package:notalone/core/result/result.dart';
import 'package:notalone/features/transcript/domain/screen_wake_lock.dart';
import 'package:notalone/features/transcript/domain/speaker.dart';
import 'package:notalone/features/transcript/domain/speaker_directory.dart';
import 'package:notalone/features/transcript/domain/transcript_binding.dart';
import 'package:notalone/features/transcript/domain/transcript_entry.dart';
import 'package:notalone/features/transcript/domain/transcript_preferences_repository.dart';
import 'package:notalone/features/transcript/domain/transcript_text_scale.dart';

/// Liaison pilotée à la main : le test décide de ce qui sort de la fusion et
/// quand, sans monter ni serveur ni `MergeTranscriptsUseCase`.
class FakeTranscriptBinding implements TranscriptBinding {
  final StreamController<TranscriptEntry> _entries =
      StreamController<TranscriptEntry>.broadcast();

  bool isDisposed = false;

  @override
  Stream<TranscriptEntry> get entries => _entries.stream;

  /// Émet [entry] et laisse la boucle d'événements la livrer.
  ///
  /// Une **microtâche** et non un `Future.delayed` : sous l'horloge simulée des
  /// widget tests, un minuteur de durée nulle n'arrive jamais à échéance tant
  /// que personne ne pompe, et l'attente ne se résout pas. Les microtâches,
  /// elles, s'écoulent normalement — et c'est bien en microtâche qu'un
  /// `StreamController` livre ce qu'on lui donne.
  Future<void> emit(TranscriptEntry entry) async {
    _entries.add(entry);
    await Future<void>.microtask(() {});
  }

  @override
  Future<void> dispose() async {
    isDisposed = true;
    await _entries.close();
  }
}

class FakeSpeakerDirectory implements SpeakerDirectory {
  FakeSpeakerDirectory([List<Speaker> initial = const []])
    : _speakers = [...initial];

  List<Speaker> _speakers;

  final StreamController<List<Speaker>> _changes =
      StreamController<List<Speaker>>.broadcast();

  bool isDisposed = false;

  @override
  List<Speaker> get speakers => List.unmodifiable(_speakers);

  @override
  Stream<List<Speaker>> get changes => _changes.stream;

  @override
  Speaker? speakerOf(String participantId) =>
      _speakers.where((speaker) => speaker.id == participantId).firstOrNull;

  /// Remplace l'annuaire et prévient, comme le ferait une admission.
  Future<void> replaceWith(List<Speaker> speakers) async {
    _speakers = [...speakers];
    _changes.add(this.speakers);
    await Future<void>.microtask(() {});
  }

  @override
  Future<void> dispose() async {
    isDisposed = true;
    await _changes.close();
  }
}

class FakeTranscriptPreferences implements TranscriptPreferencesRepository {
  FakeTranscriptPreferences({
    this.stored = TranscriptTextScale.initial,
    this.readFailure,
    this.writeFailure,
  });

  TranscriptTextScale stored;
  Failure? readFailure;
  Failure? writeFailure;

  final List<TranscriptTextScale> written = [];

  @override
  Future<Result<TranscriptTextScale>> readTextScale() async {
    final failure = readFailure;
    return failure == null ? Result.ok(stored) : Result.err(failure);
  }

  @override
  Future<Result<void>> writeTextScale(TranscriptTextScale scale) async {
    written.add(scale);
    final failure = writeFailure;
    if (failure != null) return Result.err(failure);
    stored = scale;
    return const Result.ok(null);
  }
}

class FakeScreenWakeLock implements ScreenWakeLock {
  bool isEnabled = false;
  int enableCount = 0;
  int releaseCount = 0;

  @override
  Future<void> enable() async {
    isEnabled = true;
    enableCount++;
  }

  @override
  Future<void> release() async {
    isEnabled = false;
    releaseCount++;
  }
}

/// Entrée de fil prête à l'emploi : seuls les champs qui comptent pour un test
/// donné sont nommés, le reste est plausible.
TranscriptEntry entry({
  required String participantId,
  required String text,
  String? segmentId,
  int tStartMs = 0,
  int durationMs = 900,
  double energyDb = -20,
  bool isLate = false,
}) => TranscriptEntry(
  segmentId: segmentId ?? '$participantId-$tStartMs',
  participantId: participantId,
  text: text,
  tStartMs: tStartMs,
  tEndMs: tStartMs + durationMs,
  energyDb: energyDb,
  engine: 'fake',
  isLate: isLate,
);
