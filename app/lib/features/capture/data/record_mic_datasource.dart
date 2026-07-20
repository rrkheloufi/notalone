import 'dart:async';
import 'dart:typed_data';

import 'package:notalone/core/result/result.dart';
import 'package:notalone/features/capture/domain/capture_failure.dart';
import 'package:notalone/features/capture/domain/mic_audio_source.dart';
import 'package:record/record.dart';

/// Capture micro continue en PCM 16 bits via le package `record`, convertie
/// en frames float de taille fixe. Le flux reste en mémoire : rien n'est
/// écrit sur disque (CLAUDE.md règle 2). AGC, annulation d'écho et
/// réduction de bruit restent désactivés (défauts de `RecordConfig`) :
/// l'énergie brute doit refléter la distance à la bouche (doc 02 §1).
///
/// Les interruptions sont déléguées au package, qui fait la même chose des
/// deux côtés : il observe `AVAudioSession.interruptionNotification` sur iOS
/// et l'`AudioFocusRequest` sur Android, met la capture en pause à la perte
/// et la reprend au retour. C'est ce qui évite un platform channel maison
/// pour le `mic_status` (doc 02 §8).
class RecordMicDatasource implements MicAudioSource {
  AudioRecorder? _recorder;
  StreamSubscription<RecordState>? _stateSubscription;

  final _states = StreamController<MicSourceState>.broadcast();

  @override
  Stream<MicSourceState> get state => _states.stream;

  @override
  Future<Result<Stream<Float32List>>> start({
    required int sampleRate,
    required int frameSize,
  }) async {
    try {
      await stop();
      final recorder = AudioRecorder();
      _recorder = recorder;
      if (!await recorder.hasPermission()) {
        return const Result.err(MicPermissionFailure());
      }
      _stateSubscription = recorder.onStateChanged().listen(_onRecordState);
      final bytes = await recorder.startStream(
        RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: sampleRate,
          numChannels: 1,
          // Sans quoi une interruption arrête la capture pour de bon : c'est
          // ce mode qui rend la reprise automatique après un appel entrant.
          audioInterruption: AudioInterruptionMode.pauseResume,
        ),
      );
      return Result.ok(_frames(bytes, frameSize));
    } on Exception catch (exception) {
      return Result.err(MicCaptureFailure('$exception'));
    }
  }

  @override
  Future<void> stop() async {
    final recorder = _recorder;
    _recorder = null;
    await _stateSubscription?.cancel();
    _stateSubscription = null;
    if (recorder == null) return;
    try {
      await recorder.stop();
      await recorder.dispose();
    } on Exception {
      // Arrêt best-effort : le recorder est abandonné quoi qu'il arrive.
    }
  }

  Future<void> dispose() async {
    await stop();
    await _states.close();
  }

  void _onRecordState(RecordState state) {
    if (_states.isClosed) return;
    _states.add(switch (state) {
      RecordState.record => MicSourceState.recording,
      RecordState.pause => MicSourceState.interrupted,
      RecordState.stop => MicSourceState.stopped,
    });
  }

  /// Redécoupe le flux d'octets PCM16 LE en frames de [frameSize] samples,
  /// en conservant le reliquat entre deux chunks (un chunk peut couper un
  /// sample de 16 bits en deux).
  Stream<Float32List> _frames(Stream<Uint8List> source, int frameSize) async* {
    final frameBytes = frameSize * 2;
    var pending = Uint8List(0);
    await for (final chunk in source) {
      final merged = Uint8List(pending.length + chunk.length)
        ..setRange(0, pending.length, pending)
        ..setRange(pending.length, pending.length + chunk.length, chunk);
      pending = merged;

      var offset = 0;
      while (pending.length - offset >= frameBytes) {
        yield _frameFromBytes(pending, offset, frameSize);
        offset += frameBytes;
      }
      if (offset > 0) {
        pending = Uint8List.fromList(Uint8List.sublistView(pending, offset));
      }
    }
  }

  Float32List _frameFromBytes(Uint8List bytes, int offset, int frameSize) {
    final view = ByteData.sublistView(bytes, offset, offset + frameSize * 2);
    final frame = Float32List(frameSize);
    for (var i = 0; i < frameSize; i++) {
      frame[i] = view.getInt16(i * 2, Endian.little) / 32768;
    }
    return frame;
  }
}
