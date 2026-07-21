import 'package:meta/meta.dart';
import 'package:notalone/features/transcript/domain/speaker.dart';
import 'package:notalone/features/transcript/domain/transcript_entry.dart';

/// Une prise de parole prête à être affichée : l'entrée fusionnée et le
/// locuteur auquel elle s'attribue. C'est le résultat de la jointure que
/// MVP-11 a délibérément laissée à l'écran (`TranscriptEntry` ne porte qu'un
/// `participantId`).
@immutable
class TranscriptMessage {
  const TranscriptMessage({required this.entry, required this.speaker});

  final TranscriptEntry entry;

  /// Nul si l'annuaire ne connaît pas encore cet identifiant. Le fil affiche
  /// alors la phrase sans prénom plutôt que de la retenir : une phrase
  /// anonyme reste lisible, une phrase absente est perdue.
  final Speaker? speaker;

  String get participantId => entry.participantId;

  String get text => entry.text;

  bool get isLate => entry.isLate;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TranscriptMessage &&
          other.entry == entry &&
          other.speaker == speaker);

  @override
  int get hashCode => Object.hash(entry, speaker);

  @override
  String toString() => 'TranscriptMessage(${speaker?.name ?? '?'}: $text)';
}
