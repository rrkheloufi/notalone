import 'package:notalone/core/result/result.dart';
import 'package:notalone/features/transcript/domain/transcript_text_scale.dart';

/// La taille de lecture choisie par le lecteur, persistée localement.
///
/// Elle survit à la session parce qu'elle décrit une **vue**, pas une
/// conversation : la régler à chaque repas serait une friction pour la seule
/// personne que cette app existe pour servir. Rien du fil lui-même n'est
/// stocké (CLAUDE.md règle 5).
///
/// MVP-13 branchera le même repository sur l'écran Réglages ; le fil n'a alors
/// rien à changer.
abstract interface class TranscriptPreferencesRepository {
  Future<Result<TranscriptTextScale>> readTextScale();

  Future<Result<void>> writeTextScale(TranscriptTextScale scale);
}
