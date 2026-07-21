import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:notalone/core/command/command.dart';
import 'package:notalone/core/result/result.dart';
import 'package:notalone/features/transcript/domain/screen_wake_lock.dart';
import 'package:notalone/features/transcript/domain/speaker.dart';
import 'package:notalone/features/transcript/domain/speaker_directory.dart';
import 'package:notalone/features/transcript/domain/transcript_binding.dart';
import 'package:notalone/features/transcript/domain/transcript_entry.dart';
import 'package:notalone/features/transcript/domain/transcript_preferences_repository.dart';
import 'package:notalone/features/transcript/domain/transcript_text_scale.dart';
import 'package:notalone/features/transcript/presentation/transcript_message.dart';

/// Le fil du lecteur (cf. cowork/01-cadrage-produit.md §3). Il tient l'état de
/// l'écran ; le rendu, les gestes et le contrôleur de défilement sont à la vue.
///
/// **Construit avec la session, pas avec l'écran** : les `entries` de la
/// liaison forment un flux diffusé sans rejeu : une phrase dite pendant que
/// l'hôte regarde encore le QR serait perdue si l'abonnement attendait
/// l'ouverture du fil. Il possède en retour la liaison et l'annuaire, et les
/// ferme (reprise de la propriété annoncée en clôture de MVP-11).
class TranscriptViewModel extends ChangeNotifier {
  TranscriptViewModel({
    required this._binding,
    required this._speakers,
    required this._preferences,
    required this._wakeLock,
  }) {
    _subscriptions
      ..add(_binding.entries.listen(_onEntry))
      ..add(_speakers.changes.listen(_onSpeakersChanged));
  }

  final TranscriptBinding _binding;
  final SpeakerDirectory _speakers;
  final TranscriptPreferencesRepository _preferences;
  final ScreenWakeLock _wakeLock;

  final List<StreamSubscription<void>> _subscriptions = [];

  late final Command0<void> loadCommand = Command0(_load);
  late final Command0<void> enlargeTextCommand = Command0(_enlargeText);
  late final Command0<void> reduceTextCommand = Command0(_reduceText);

  /// Un repas de 2 h tourne autour de 900 entrées (mesure de charge MVP-11) :
  /// ce plafond laisse de la marge pour remonter tout un repas, et borne la
  /// mémoire d'une session qui s'éterniserait. Ce sont les plus anciennes qui
  /// partent — le fil est éphémère par principe (CLAUDE.md règle 5).
  static const int maxMessages = 2000;

  final List<TranscriptMessage> _messages = [];

  /// Tout le fil, dans l'ordre où il s'est écrit.
  List<TranscriptMessage> get messages => List.unmodifiable(_messages);

  /// Ce que le lecteur voit, filtre appliqué.
  List<TranscriptMessage> get visibleMessages => List.unmodifiable(
    _speakerFilter == null
        ? _messages
        : _messages.where((message) => message.participantId == _speakerFilter),
  );

  List<Speaker> get speakers => _speakers.speakers;

  String? _speakerFilter;

  /// Identifiant du locuteur isolé, nul quand tout le monde s'affiche.
  String? get speakerFilter => _speakerFilter;

  bool get isFiltered => _speakerFilter != null;

  Speaker? get filteredSpeaker =>
      _speakerFilter == null ? null : _speakers.speakerOf(_speakerFilter!);

  TranscriptTextScale _textScale = TranscriptTextScale.initial;
  TranscriptTextScale get textScale => _textScale;

  /// Vrai tant que le fil suit les nouvelles phrases. Passe à faux dès que le
  /// lecteur remonte : à partir de là, plus rien ne bouge sous ses yeux
  /// (doc 01 §3, « jamais de scroll forcé »).
  bool _isFollowing = true;
  bool get isFollowing => _isFollowing;

  /// Phrases arrivées depuis que le lecteur a quitté le bas du fil : c'est le
  /// « N » du badge. Compté sur les messages **visibles** — un filtre actif
  /// doit compter ce que le badge promet de montrer.
  int _unreadCount = 0;
  int get unreadCount => _unreadCount;

  bool get hasUnread => _unreadCount > 0;

  /// Lit la taille persistée et allume le verrou d'écran. L'échec de l'un
  /// n'empêche pas l'autre : ni la taille par défaut ni un écran qui s'éteint
  /// ne justifient de refuser le fil au lecteur.
  Future<Result<void>> _load() async {
    unawaited(_wakeLock.enable());
    final read = await _preferences.readTextScale();
    _textScale = read.valueOrNull ?? TranscriptTextScale.initial;
    notifyListeners();
    return read.map((_) {});
  }

  Future<Result<void>> _enlargeText() => _applyTextScale(_textScale.larger);

  Future<Result<void>> _reduceText() => _applyTextScale(_textScale.smaller);

  /// La taille change à l'écran d'abord, puis se persiste : un stockage lent
  /// ou en panne ne doit pas retarder le geste. L'échec remonte quand même
  /// dans le `Result` — c'est la vue qui décide d'en parler ou non.
  Future<Result<void>> _applyTextScale(TranscriptTextScale scale) async {
    if (scale == _textScale) return const Result.ok(null);
    _textScale = scale;
    notifyListeners();
    return _preferences.writeTextScale(scale);
  }

  /// Isole un locuteur, ou le désisole si c'était déjà lui : le même appui sur
  /// un prénom active et désactive le filtre — le geste unique du critère
  /// d'acceptation.
  void toggleSpeakerFilter(String participantId) => _setSpeakerFilter(
    _speakerFilter == participantId ? null : participantId,
  );

  void clearSpeakerFilter() => _setSpeakerFilter(null);

  /// La vue signale que le fil est revenu au plus récent (ou l'a quitté).
  /// L'état de défilement appartient au contrôleur, qui est un objet de
  /// widget : le ViewModel en reçoit la conclusion, il ne l'observe pas.
  void setFollowing({required bool following}) {
    if (_isFollowing == following) return;
    _isFollowing = following;
    if (following) _unreadCount = 0;
    notifyListeners();
  }

  void _setSpeakerFilter(String? participantId) {
    if (_speakerFilter == participantId) return;
    _speakerFilter = participantId;
    // Le contenu de la liste vient de changer entièrement : la position de
    // défilement d'avant ne désigne plus rien. On se réancre sur le plus
    // récent, et le compteur repart de zéro puisque tout est à relire.
    _isFollowing = true;
    _unreadCount = 0;
    notifyListeners();
  }

  void _onEntry(TranscriptEntry entry) {
    final message = TranscriptMessage(
      entry: entry,
      speaker: _speakers.speakerOf(entry.participantId),
    );
    // Une entrée tardive s'ajoute **à la fin**, comme les autres, alors même
    // qu'elle est chronologiquement antérieure : l'insérer à sa place ferait
    // sauter le texte déjà lu, ce que le doc 02 §5.2 interdit. Elle est
    // signalée dans la bulle plutôt que déplacée.
    _messages.add(message);
    if (_messages.length > maxMessages) _messages.removeAt(0);
    if (!_isFollowing && _matchesFilter(message)) _unreadCount++;
    notifyListeners();
  }

  void _onSpeakersChanged(List<Speaker> speakers) {
    // Un convive arrivé après coup — ou renommé — doit voir son prénom
    // apparaître sur les phrases déjà affichées : la jointure se rejoue sur
    // tout le fil, pas seulement sur les prochaines entrées.
    for (var i = 0; i < _messages.length; i++) {
      final message = _messages[i];
      final speaker = _speakers.speakerOf(message.participantId);
      if (speaker != message.speaker) {
        _messages[i] = TranscriptMessage(
          entry: message.entry,
          speaker: speaker,
        );
      }
    }
    notifyListeners();
  }

  bool _matchesFilter(TranscriptMessage message) =>
      _speakerFilter == null || message.participantId == _speakerFilter;

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(_wakeLock.release());
    unawaited(_speakers.dispose());
    unawaited(_binding.dispose());
    _messages.clear();
    loadCommand.dispose();
    enlargeTextCommand.dispose();
    reduceTextCommand.dispose();
    super.dispose();
  }
}
