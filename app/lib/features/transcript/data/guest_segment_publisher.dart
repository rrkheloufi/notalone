import 'package:notalone/features/capture/domain/segment_publisher.dart';
import 'package:notalone/features/capture/domain/transcribed_segment.dart';
import 'package:notalone/features/session/domain/guest_client.dart';
import 'package:notalone/features/session/domain/protocol/session_message.dart';

/// Met les segments transcrits de l'invité sur le fil, en `speech_segment`
/// (cf. cowork/02-architecture.md §4).
///
/// C'est le seul endroit qui traduit une entité de `capture/` en DTO de
/// `session/` : les deux features s'ignorent, cet adaptateur de `transcript/`
/// les connaît (CLAUDE.md règle 3).
///
/// Rien à faire des coupures réseau : [GuestClient.send] met en file et
/// réémet à la reconnexion (MVP-06). Un segment produit pendant que le WiFi
/// vacille n'est donc pas perdu, il arrive en retard — et le buffer de
/// réordonnancement de l'hôte le placera, ou le marquera tardif.
class GuestSegmentPublisher implements SegmentPublisher {
  const GuestSegmentPublisher({required this._client});

  final GuestClient _client;

  @override
  void publish(TranscribedSegment segment) => _client.send(
    SpeechSegmentDto(
      segmentId: segment.segmentId,
      // Horodatages epoch de **ce** téléphone : c'est l'hôte qui les corrigera
      // de l'offset d'horloge mesuré pour cet invité (doc 02 §5.1).
      tStartMs: segment.tStartMs,
      tEndMs: segment.tEndMs,
      text: segment.text,
      isFinal: segment.transcription.isFinal,
      energyDb: segment.energyDbfs,
      engine: segment.transcription.engine,
    ),
  );

  /// Le client appartient au parcours « Rejoindre », qui le ferme lui-même :
  /// le publieur n'a rien à libérer.
  @override
  Future<void> dispose() async {}
}
