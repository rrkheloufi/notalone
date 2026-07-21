import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:notalone/core/command/command.dart';
import 'package:notalone/core/result/failure.dart';
import 'package:notalone/core/result/result.dart';
import 'package:notalone/features/capture/domain/capture_speech_use_case.dart';
import 'package:notalone/features/capture/domain/capture_status.dart';
import 'package:notalone/features/capture/domain/segment_publisher.dart';
import 'package:notalone/features/capture/domain/speech_segment.dart';
import 'package:notalone/features/capture/domain/transcribe_segments_use_case.dart';
import 'package:notalone/features/capture/domain/transcribed_segment.dart';

/// Écran de capture de l'invité : état du micro, prises de parole détectées et
/// texte que le moteur STT en a tiré.
///
/// Ouvert depuis une session, il publie chaque segment transcrit via son
/// [SegmentPublisher] ; ouvert depuis l'accueil, il ne publie rien et sert à
/// vérifier son micro. Dans les deux cas il rend visible ce que ce téléphone
/// capte et comprend, ce qui permet de dérouler sur appareil réel la checklist
/// d'interruptions (MVP-08) et les 10 phrases scriptées (MVP-10).
class CaptureViewModel extends ChangeNotifier {
  CaptureViewModel({
    required this._capture,
    required this._transcribe,
    this._publisher,
  }) {
    startCommand = Command0(_start);
    stopCommand = Command0(_stop);
    toggleMuteCommand = Command0(_toggleMute);
    _subscriptions
      ..add(_capture.segments.listen(_onSegment))
      ..add(_capture.statuses.listen(_onStatus))
      ..add(_capture.speaking.listen((_) => notifyListeners()))
      ..add(_capture.failures.listen(_onFailure))
      ..add(_transcribe.transcriptions.listen(_onTranscription))
      ..add(_transcribe.failures.listen(_onTranscriptionFailure));
  }

  final CaptureSpeechUseCase _capture;
  final TranscribeSegmentsUseCase _transcribe;

  /// Nul quand l'écran est ouvert hors session (« mon micro » depuis
  /// l'accueil) : on capte et on transcrit pour vérifier son matériel, sans
  /// rien envoyer à personne.
  final SegmentPublisher? _publisher;

  final List<StreamSubscription<void>> _subscriptions = [];

  late final Command0<void> startCommand;
  late final Command0<void> stopCommand;
  late final Command0<void> toggleMuteCommand;

  CaptureStatus get status => _capture.status;

  bool get isCapturing => _capture.isStarted;

  bool get isSpeaking => _capture.isSpeaking;

  int get discardedSegments => _capture.discardedSegments;

  /// Moteur STT réellement retenu par la plateforme, connu après `prepare()`.
  /// Affiché pour que le test manuel des 10 phrases sache lequel des quatre
  /// moteurs de la matrice (doc 02 §3) a produit le texte.
  String get engine => _transcribe.capabilities.engine;

  /// Panne survenue en cours de flux : la capture s'est arrêtée d'elle-même.
  Failure? _streamFailure;
  Failure? get streamFailure => _streamFailure;

  /// Panne du moteur STT. Distincte de [streamFailure] : le micro, lui,
  /// continue de tourner — l'invité reste visible chez l'hôte et pourra
  /// basculer sur le moteur cloud (MVP-14) sans redémarrer sa session.
  Failure? _sttFailure;
  Failure? get sttFailure => _sttFailure;

  /// Les derniers segments seulement : le transcript complet est le métier de
  /// `transcript/` (MVP-12), pas celui de cet écran.
  static const int maxVisibleSegments = 20;

  final List<SpeechSegment> _segments = [];
  List<SpeechSegment> get segments => List.unmodifiable(_segments);

  final Map<String, TranscribedSegment> _transcriptions = {};

  /// Texte reconnu pour ce segment, ou `null` tant que le moteur travaille.
  TranscribedSegment? transcriptionOf(String segmentId) =>
      _transcriptions[segmentId];

  /// Vérifie le moteur STT **puis** démarre le micro. Un modèle absent ou une
  /// autorisation refusée ne bloquent pas la capture : les prises de parole
  /// restent détectées et l'invité reste supervisé côté hôte (MVP-13). La
  /// panne est affichée en continu plutôt que d'interdire la session.
  Future<Result<void>> _start() async {
    final prepared = await _transcribe.prepare();
    _sttFailure = prepared.failureOrNull;
    notifyListeners();
    return _capture.start();
  }

  Future<Result<void>> _stop() async {
    await _capture.stop();
    notifyListeners();
    return const Result.ok(null);
  }

  Future<Result<void>> _toggleMute() =>
      _capture.setMuted(muted: status != CaptureStatus.muted);

  void _onSegment(SpeechSegment segment) {
    _segments.insert(0, segment);
    if (_segments.length > maxVisibleSegments) {
      // Le texte du segment oublié n'a plus d'écran où s'afficher : sans ce
      // nettoyage la table grossirait pendant tout le repas.
      _transcriptions.remove(_segments.removeLast().segmentId);
    }
    _transcribe.submit(segment);
    notifyListeners();
  }

  void _onTranscription(TranscribedSegment transcribed) {
    _sttFailure = null;
    _transcriptions[transcribed.segmentId] = transcribed;
    // Le texte part sur le fil ici et nulle part ailleurs : c'est le dernier
    // point du pipeline invité (doc 02 §1). L'audio, lui, est déjà mort avec
    // le `SpeechSegment` (CLAUDE.md règle 2).
    _publisher?.publish(transcribed);
    notifyListeners();
  }

  void _onTranscriptionFailure(Failure failure) {
    _sttFailure = failure;
    notifyListeners();
  }

  void _onStatus(CaptureStatus status) {
    if (status == CaptureStatus.active) _streamFailure = null;
    notifyListeners();
  }

  void _onFailure(Failure failure) {
    _streamFailure = failure;
    notifyListeners();
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(_capture.dispose());
    unawaited(_transcribe.dispose());
    unawaited(_publisher?.dispose());
    startCommand.dispose();
    stopCommand.dispose();
    toggleMuteCommand.dispose();
    super.dispose();
  }
}
