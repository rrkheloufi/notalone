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
class RecordMicDatasource implements MicAudioSource {
  AudioRecorder? _recorder;

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
      final bytes = await recorder.startStream(
        RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: sampleRate,
          numChannels: 1,
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
    if (recorder == null) return;
    try {
      await recorder.stop();
      await recorder.dispose();
    } on Exception {
      // Arrêt best-effort : le recorder est abandonné quoi qu'il arrive.
    }
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
