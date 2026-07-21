import 'package:notalone/features/transcript/domain/transcript_entry.dart';

/// Ce qui relie une session vivante à la fusion : quelqu'un alimente le
/// `MergeTranscriptsUseCase` depuis le transport, et publie le fil qui en sort.
///
/// Interface plutôt que classe concrète pour que la présentation puisse tenir
/// le cycle de vie de la liaison sans connaître `session/` ni le transport
/// (CLAUDE.md règle 3). L'implémentation vit dans `transcript/data/`.
abstract interface class TranscriptBinding {
  Stream<TranscriptEntry> get entries;

  /// Ferme la liaison et la fusion qu'elle alimente. Le fil est éphémère :
  /// rien n'en survit (CLAUDE.md règle 5).
  Future<void> dispose();
}
