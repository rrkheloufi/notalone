import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:notalone/core/command/command.dart';
import 'package:notalone/core/result/failure.dart';
import 'package:notalone/core/result/result.dart';
import 'package:notalone/features/capture/domain/capture_speech_use_case.dart';
import 'package:notalone/features/capture/domain/capture_status.dart';
import 'package:notalone/features/capture/domain/speech_segment.dart';

/// Écran de capture de l'invité : état du micro et segments détectés.
///
/// Il ne transcrit ni n'envoie rien encore (MVP-10 et MVP-13) — il rend
/// visible ce que le pipeline capte, ce qui est aussi ce qui permet de
/// dérouler la checklist d'interruptions sur appareil réel.
class CaptureViewModel extends ChangeNotifier {
  CaptureViewModel({required this._capture}) {
    startCommand = Command0(_capture.start);
    stopCommand = Command0(_stop);
    toggleMuteCommand = Command0(_toggleMute);
    _subscriptions
      ..add(_capture.segments.listen(_onSegment))
      ..add(_capture.statuses.listen(_onStatus))
      ..add(_capture.speaking.listen((_) => notifyListeners()))
      ..add(_capture.failures.listen(_onFailure));
  }

  final CaptureSpeechUseCase _capture;
  final List<StreamSubscription<void>> _subscriptions = [];

  late final Command0<void> startCommand;
  late final Command0<void> stopCommand;
  late final Command0<void> toggleMuteCommand;

  CaptureStatus get status => _capture.status;

  bool get isCapturing => _capture.isStarted;

  bool get isSpeaking => _capture.isSpeaking;

  int get discardedSegments => _capture.discardedSegments;

  /// Panne survenue en cours de flux : la capture s'est arrêtée d'elle-même.
  Failure? _streamFailure;
  Failure? get streamFailure => _streamFailure;

  /// Les derniers segments seulement : le transcript complet est le métier de
  /// `transcript/` (MVP-12), pas celui de cet écran.
  static const int maxVisibleSegments = 20;

  final List<SpeechSegment> _segments = [];
  List<SpeechSegment> get segments => List.unmodifiable(_segments);

  Future<Result<void>> _stop() async {
    await _capture.stop();
    notifyListeners();
    return const Result.ok(null);
  }

  Future<Result<void>> _toggleMute() =>
      _capture.setMuted(muted: status != CaptureStatus.muted);

  void _onSegment(SpeechSegment segment) {
    _segments.insert(0, segment);
    if (_segments.length > maxVisibleSegments) _segments.removeLast();
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
    startCommand.dispose();
    stopCommand.dispose();
    toggleMuteCommand.dispose();
    super.dispose();
  }
}
