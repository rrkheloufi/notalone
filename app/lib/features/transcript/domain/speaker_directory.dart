import 'package:notalone/features/transcript/domain/speaker.dart';

/// Qui est qui, pour l'écran du fil. Les `TranscriptEntry` ne portent qu'un
/// `participantId` (décision MVP-11) : c'est ici que la jointure se fait.
///
/// Interface parce que la source réelle est le registre du serveur hôte, dans
/// `session/` — l'implémentation vit dans `transcript/data/`, et le ViewModel
/// n'en sait rien.
abstract interface class SpeakerDirectory {
  /// Les locuteurs connus de la session, hôte compris.
  List<Speaker> get speakers;

  /// Émet à chaque fois que [speakers] change : un convive qui arrive en cours
  /// de repas doit voir son prénom apparaître sur les phrases déjà affichées,
  /// pas seulement sur les suivantes.
  Stream<List<Speaker>> get changes;

  Speaker? speakerOf(String participantId);

  /// L'annuaire suit une source vivante : il se ferme avec la session.
  Future<void> dispose();
}
