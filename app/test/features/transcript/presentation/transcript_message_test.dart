import 'package:flutter_test/flutter_test.dart';
import 'package:notalone/features/transcript/domain/speaker.dart';
import 'package:notalone/features/transcript/presentation/transcript_message.dart';

import '../../../helpers/fake_transcript_sources.dart';

const Speaker _papa = Speaker(id: 'p1', name: 'Papa', colorIndex: 0);

void main() {
  group('TranscriptMessage', () {
    test('reprend ce que l’écran a besoin de lire sur l’entrée', () {
      final message = TranscriptMessage(
        entry: entry(
          participantId: 'p1',
          text: 'Passe le sel',
          isLate: true,
        ),
        speaker: _papa,
      );

      expect(message.participantId, 'p1');
      expect(message.text, 'Passe le sel');
      expect(message.isLate, isTrue);
    });

    test('deux messages identiques sont égaux', () {
      final shared = entry(participantId: 'p1', text: 'Passe le sel');
      final a = TranscriptMessage(entry: shared, speaker: _papa);
      final b = TranscriptMessage(entry: shared, speaker: _papa);

      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('le même texte attribué à un autre locuteur diffère', () {
      final shared = entry(participantId: 'p1', text: 'oui');
      final attributed = TranscriptMessage(entry: shared, speaker: _papa);
      final anonymous = TranscriptMessage(entry: shared, speaker: null);

      // C'est cette comparaison qui décide de reconstruire une bulle quand
      // l'annuaire apprend un prénom.
      expect(attributed, isNot(anonymous));
    });

    test('un locuteur inconnu se décrit sans planter', () {
      final message = TranscriptMessage(
        entry: entry(participantId: 'fantome', text: 'Bonsoir'),
        speaker: null,
      );

      expect(message.toString(), contains('Bonsoir'));
    });
  });
}
