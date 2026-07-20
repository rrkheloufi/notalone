import 'package:meta/meta.dart';
import 'package:notalone/features/transcript/domain/transcript_timing_config.dart';

/// Une entrée sortie du buffer, prête à être affichée.
@immutable
class ReorderedEntry<T> {
  const ReorderedEntry({required this.value, required this.isLate});

  final T value;

  /// L'entrée est arrivée alors que du texte plus récent était déjà figé :
  /// elle sort quand même, mais hors de sa place chronologique. MVP-12
  /// décidera comment le signaler au lecteur.
  final bool isLate;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ReorderedEntry<T> &&
          other.value == value &&
          other.isLate == isLate);

  @override
  int get hashCode => Object.hash(value, isLate);
}

/// Buffer de réordonnancement de l'hôte (cf. cowork/02-architecture.md §5.2).
///
/// Les segments n'arrivent pas dans l'ordre où ils ont été prononcés : chaque
/// téléphone a sa latence STT et sa latence réseau. On retient donc chaque
/// entrée [TranscriptTimingConfig.reorderWindow] avant de l'afficher, le temps
/// qu'un segment parti plus tôt d'un autre téléphone puisse la rattraper.
/// Passé ce délai l'entrée est **figée** : plus jamais de texte qui se
/// réorganise sous les yeux du lecteur.
///
/// Passif par choix : il ne connaît ni horloge ni timer, on lui donne l'heure
/// et il rend ce qui est mûr. Déterministe à tester, et MVP-11 branchera la
/// cadence qui lui convient.
///
/// Générique : les horodatages sont ceux de l'horloge **hôte**, à l'appelant
/// de les avoir corrigés via `SyncedClock` avant d'ajouter l'entrée.
class ReorderBuffer<T> {
  ReorderBuffer({
    required this.timestampOf,
    this.config = const TranscriptTimingConfig(),
  });

  /// Où lire, dans une entrée, son instant sur l'horloge hôte.
  final int Function(T entry) timestampOf;

  final TranscriptTimingConfig config;

  final List<_Pending<T>> _waiting = [];

  /// Entrées déjà dépassées à l'arrivée : elles ne gagnent rien à attendre,
  /// leur place est perdue. File séparée pour qu'elles sortent en tête du
  /// prochain lot — elles sont plus anciennes que tout ce qui va suivre.
  final List<_Pending<T>> _late = [];

  /// Horodatage le plus récent déjà figé, `null` tant que rien n'est sorti.
  int? _lastReleasedMs;

  /// Compteur d'arrivée : départage deux entrées de même horodatage pour que
  /// l'ordre de sortie reste stable (deux convives peuvent commencer leur
  /// phrase dans la même milliseconde).
  int _sequence = 0;

  int get pending => _waiting.length + _late.length;

  bool get isEmpty => pending == 0;

  /// Instant à partir duquel [release] aura quelque chose à rendre, `null` si
  /// le buffer est vide. Permet à l'appelant de programmer son réveil au lieu
  /// d'interroger le buffer en boucle. Une échéance déjà passée signifie
  /// « il y a de quoi afficher maintenant » — c'est toujours le cas des
  /// entrées tardives.
  int? get nextDueMs {
    if (_late.isNotEmpty) return _earliestTimestampMs(_late);
    if (_waiting.isEmpty) return null;
    return _earliestTimestampMs(_waiting) + config.reorderWindowMs;
  }

  void add(T entry) {
    final pending = _Pending(
      value: entry,
      timestampMs: timestampOf(entry),
      sequence: _sequence++,
    );
    final lastReleasedMs = _lastReleasedMs;
    final isLate =
        lastReleasedMs != null && pending.timestampMs < lastReleasedMs;
    (isLate ? _late : _waiting).add(pending);
  }

  /// Rend les entrées à afficher : les tardives d'abord (elles précèdent
  /// chronologiquement tout le reste), puis celles dont la fenêtre est
  /// écoulée, dans l'ordre temporel corrigé.
  List<ReorderedEntry<T>> release(int nowMs) {
    final deadline = nowMs - config.reorderWindowMs;
    final mature = <_Pending<T>>[];
    final stillWaiting = <_Pending<T>>[];
    for (final entry in _waiting) {
      (entry.timestampMs <= deadline ? mature : stillWaiting).add(entry);
    }
    _waiting
      ..clear()
      ..addAll(stillWaiting);
    return _emit(mature);
  }

  /// Vide le buffer sans attendre : fin de session (MVP-13), il ne reste rien
  /// à rattraper et le lecteur doit voir les dernières phrases.
  List<ReorderedEntry<T>> flush() {
    final remaining = [..._waiting];
    _waiting.clear();
    return _emit(remaining);
  }

  /// Les tardives en tête, puis [mature] dans l'ordre temporel corrigé.
  /// Seules les entrées à l'heure font avancer la ligne de gel : une tardive
  /// est par définition antérieure, elle ne fige rien de plus.
  List<ReorderedEntry<T>> _emit(List<_Pending<T>> mature) {
    final released = [
      for (final entry in _late)
        ReorderedEntry(value: entry.value, isLate: true),
    ];
    _late.clear();

    mature.sort(_byTimeThenArrival);
    for (final entry in mature) {
      released.add(ReorderedEntry(value: entry.value, isLate: false));
      _lastReleasedMs = entry.timestampMs;
    }
    return released;
  }

  static int _earliestTimestampMs<T>(List<_Pending<T>> entries) => entries
      .map((entry) => entry.timestampMs)
      .reduce((a, b) => a < b ? a : b);

  static int _byTimeThenArrival<T>(_Pending<T> a, _Pending<T> b) {
    final byTime = a.timestampMs.compareTo(b.timestampMs);
    return byTime != 0 ? byTime : a.sequence.compareTo(b.sequence);
  }
}

class _Pending<T> {
  _Pending({
    required this.value,
    required this.timestampMs,
    required this.sequence,
  });

  final T value;
  final int timestampMs;
  final int sequence;
}
