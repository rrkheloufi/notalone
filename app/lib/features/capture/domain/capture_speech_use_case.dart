import 'dart:async';
import 'dart:typed_data';

import 'package:notalone/core/result/failure.dart';
import 'package:notalone/core/result/result.dart';
import 'package:notalone/features/capture/domain/background_capture_guard.dart';
import 'package:notalone/features/capture/domain/capture_status.dart';
import 'package:notalone/features/capture/domain/mic_audio_source.dart';
import 'package:notalone/features/capture/domain/speech_segment.dart';
import 'package:notalone/features/capture/domain/speech_segmenter.dart';
import 'package:notalone/features/capture/domain/vad_config.dart';
import 'package:notalone/features/capture/domain/vad_service.dart';

/// Horloge murale du pipeline, injectable comme `generateId` : sans cette
/// indirection aucun test ne pourrait vérifier l'horodatage d'un segment.
int systemNowMs() => DateTime.now().millisecondsSinceEpoch;

/// Le pipeline de capture d'un invité, de bout en bout : micro → VAD →
/// segmenteur → filtre énergie → [SpeechSegment] horodatés
/// (cf. cowork/02-architecture.md §1).
///
/// Pur Dart : le micro, le VAD et le maintien en arrière-plan sont trois
/// interfaces, ce qui rend tout le pipeline rejouable en test sur des
/// fixtures de buffers.
class CaptureSpeechUseCase {
  CaptureSpeechUseCase({
    required this._mic,
    required this._vad,
    required this._guard,
    VadConfig config = const VadConfig(),
    this.nowMs = systemNowMs,
    this.generateId = generateSegmentId,
  }) : _config = config,
       _segmenter = SpeechSegmenter(config: config);


  final MicAudioSource _mic;
  final VadService _vad;
  final BackgroundCaptureGuard _guard;
  final VadConfig _config;
  final SpeechSegmenter _segmenter;

  final int Function() nowMs;
  final String Function() generateId;

  final _segments = StreamController<SpeechSegment>.broadcast();
  final _statuses = StreamController<CaptureStatus>.broadcast();
  final _failures = StreamController<Failure>.broadcast();
  final _speaking = StreamController<bool>.broadcast();

  /// Segments retenus, prêts pour le moteur STT (MVP-10).
  Stream<SpeechSegment> get segments => _segments.stream;

  Stream<CaptureStatus> get statuses => _statuses.stream;

  /// Entrées et sorties de parole, transitions seules — une découpe forcée
  /// à `maxSegmentMs` n'y paraît pas, la parole n'ayant pas cessé.
  Stream<bool> get speaking => _speaking.stream;

  /// Pannes survenues **en cours de flux** (inférence VAD…) : `start()` ne
  /// peut pas les retourner puisqu'elle a déjà rendu la main.
  Stream<Failure> get failures => _failures.stream;

  CaptureStatus _status = CaptureStatus.idle;
  CaptureStatus get status => _status;

  /// Vraie tant que le pipeline est en marche, micro coupé par l'invité
  /// compris — seul `stop()` la remet à faux.
  bool _started = false;
  bool get isStarted => _started;

  bool get isSpeaking => _segmenter.isSpeaking;

  /// Segments écartés par le filtre énergie depuis le démarrage. Sert à
  /// objectiver la calibration du seuil en MVP-15.
  int _discardedSegments = 0;
  int get discardedSegments => _discardedSegments;

  /// Origine epoch du flux courant. Ré-ancrée à chaque reprise après
  /// interruption : le segmenteur compte des samples, or il n'en arrive
  /// aucun pendant un appel téléphonique — sans ré-ancrage, tout ce qui suit
  /// l'interruption serait daté en retard de la durée de l'appel.
  int _anchorEpochMs = 0;

  StreamSubscription<MicSourceState>? _stateSubscription;

  // Annulée par _closeFrames(), qu'appellent stop(), setMuted() et dispose() —
  // le lint ne voit pas l'annulation à travers ce niveau d'indirection.
  // ignore: cancel_subscriptions
  StreamSubscription<Float32List>? _frameSubscription;
  bool _resumePending = false;
  bool _wasSpeaking = false;

  Future<Result<void>> start() async {
    if (_started) return const Result.ok(null);

    final acquired = await _guard.acquire();
    if (acquired case Err(:final failure)) return Result.err(failure);

    final initialized = await _vad.initialize();
    if (initialized case Err(:final failure)) {
      await _guard.release();
      return Result.err(failure);
    }

    final started = await _mic.start(
      sampleRate: _config.sampleRate,
      frameSize: _config.frameSize,
    );
    switch (started) {
      case Err(:final failure):
        await _guard.release();
        return Result.err(failure);
      case Ok(:final value):
        _segmenter.reset();
        await _vad.reset();
        _discardedSegments = 0;
        _anchorEpochMs = nowMs();
        _started = true;
        _stateSubscription = _mic.state.listen(_onMicState);
        _setStatus(CaptureStatus.active);
        _listen(value);
        return const Result.ok(null);
    }
  }

  Future<void> stop() async {
    if (!_started) return;
    _started = false;
    await _stateSubscription?.cancel();
    _stateSubscription = null;
    await _closeFrames();
    await _mic.stop();
    _emitSegment(_segmenter.flush());
    _setSpeaking(false);
    await _guard.release();
    _setStatus(CaptureStatus.idle);
  }

  /// Coupe (ou rallume) le micro à la demande de l'invité. Le micro est
  /// réellement relâché : rien ne sert de le tenir allumé pour un flux qu'on
  /// jette, et la batterie d'un repas de 2 h se ménage (doc 03 R1).
  Future<Result<void>> setMuted({required bool muted}) async {
    if (!_started || muted == (_status == CaptureStatus.muted)) {
      return const Result.ok(null);
    }
    if (muted) {
      await _stateSubscription?.cancel();
      _stateSubscription = null;
      await _closeFrames();
      await _mic.stop();
      _emitSegment(_segmenter.flush());
      _setSpeaking(false);
      _setStatus(CaptureStatus.muted);
      return const Result.ok(null);
    }

    final started = await _mic.start(
      sampleRate: _config.sampleRate,
      frameSize: _config.frameSize,
    );
    switch (started) {
      case Err(:final failure):
        return Result.err(failure);
      case Ok(:final value):
        _segmenter.reset();
        await _vad.reset();
        _anchorEpochMs = nowMs();
        _stateSubscription = _mic.state.listen(_onMicState);
        _setStatus(CaptureStatus.active);
        _listen(value);
        return const Result.ok(null);
    }
  }

  /// Consomme les frames une par une, la souscription **en pause** le temps
  /// de l'inférence : sans cette contre-pression, un VAD plus lent que le
  /// micro verrait les frames s'empiler sans fin en mémoire.
  void _listen(Stream<Float32List> frames) {
    _frameSubscription = frames.listen(_onFrame);
  }

  void _onFrame(Float32List frame) {
    final subscription = _frameSubscription;
    if (subscription == null) return;
    subscription.pause();
    unawaited(
      _processFrame(frame).whenComplete(() {
        // La souscription a pu être annulée pendant l'inférence.
        if (identical(_frameSubscription, subscription) &&
            subscription.isPaused) {
          subscription.resume();
        }
      }),
    );
  }

  Future<void> _processFrame(Float32List frame) async {
    if (!_started) return;
    if (_resumePending) {
      _resumePending = false;
      _segmenter.reset();
      await _vad.reset();
      _anchorEpochMs = nowMs();
    }
    final prediction = await _vad.predictSpeechProbability(frame);
    if (prediction case Err(:final failure)) {
      if (!_failures.isClosed) _failures.add(failure);
      await _closeFrames();
      unawaited(_mic.stop());
      return;
    }
    final probability = (prediction as Ok<double>).value;
    _emitSegment(_segmenter.addFrame(frame, probability));
    _setSpeaking(_segmenter.isSpeaking);
  }

  /// Coupe l'arrivée des frames sans dépendre de la fermeture du flux amont :
  /// un micro qui ne rend pas la main ne doit pas figer `stop()`.
  Future<void> _closeFrames() async {
    final subscription = _frameSubscription;
    _frameSubscription = null;
    await subscription?.cancel();
  }

  void _setSpeaking(bool speaking) {
    if (_speaking.isClosed || speaking == _wasSpeaking) return;
    _wasSpeaking = speaking;
    _speaking.add(speaking);
  }

  void _onMicState(MicSourceState state) {
    switch (state) {
      case MicSourceState.interrupted:
        // L'invité était peut-être en pleine phrase quand l'appel est tombé :
        // ce qui a été capté part quand même vers le STT.
        _emitSegment(_segmenter.flush());
        _setSpeaking(false);
        _setStatus(CaptureStatus.interrupted);
      case MicSourceState.recording:
        if (_status == CaptureStatus.interrupted) _resumePending = true;
        _setStatus(CaptureStatus.active);
      case MicSourceState.stopped:
        break;
    }
  }

  void _emitSegment(SegmenterEvent? event) {
    if (event is! SpeechEnded) return;
    final raw = event.segment;
    // Filtre énergie : un segment sous le plancher est du bruit ou une voix
    // trop lointaine pour être transcrite utilement (VadConfig).
    if (raw.energyDbfs < _config.minSegmentEnergyDbfs) {
      _discardedSegments++;
      return;
    }
    _segments.add(
      SpeechSegment(
        segmentId: generateId(),
        tStartMs: _anchorEpochMs + raw.tStartMs,
        tEndMs: _anchorEpochMs + raw.tEndMs,
        energyDbfs: raw.energyDbfs,
        samples: raw.samples,
        sampleRate: _config.sampleRate,
      ),
    );
  }

  void _setStatus(CaptureStatus status) {
    if (_status == status) return;
    _status = status;
    _statuses.add(status);
  }

  Future<void> dispose() async {
    await stop();
    await _vad.dispose();
    await _segments.close();
    await _statuses.close();
    await _failures.close();
    await _speaking.close();
  }
}
