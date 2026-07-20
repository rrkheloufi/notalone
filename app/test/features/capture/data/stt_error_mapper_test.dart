import 'package:flutter_test/flutter_test.dart';
import 'package:notalone/features/capture/data/stt_error_mapper.dart';
import 'package:notalone/features/capture/domain/stt_failure.dart';

void main() {
  group('sttFailureFromCode', () {
    test('traduit chaque code du contrat natif', () {
      expect(
        sttFailureFromCode(SttErrorCode.unavailable),
        isA<SttUnavailableFailure>(),
      );
      expect(
        sttFailureFromCode(SttErrorCode.modelMissing),
        isA<SttModelMissingFailure>(),
      );
      expect(
        sttFailureFromCode(SttErrorCode.permissionDenied),
        isA<SttPermissionFailure>(),
      );
      expect(
        sttFailureFromCode(SttErrorCode.audioSourceUnsupported),
        isA<SttAudioSourceUnsupportedFailure>(),
      );
      expect(
        sttFailureFromCode(SttErrorCode.timeout),
        isA<SttTimeoutFailure>(),
      );
      expect(
        sttFailureFromCode(SttErrorCode.failed),
        isA<SttTranscriptionFailure>(),
      );
    });

    test('rabat un code inconnu sur une panne de transcription', () {
      final failure = sttFailureFromCode('code_jamais_vu', details: 'bizarre');

      expect(failure, isA<SttTranscriptionFailure>());
      expect(failure.message, contains('bizarre'));
    });

    test('reprend le détail natif dans le message', () {
      final failure = sttFailureFromCode(
        SttErrorCode.audioSourceUnsupported,
        details: 'le moteur refuse le tube',
      );

      expect(failure.message, contains('le moteur refuse le tube'));
    });

    test('retombe sur le code quand le natif ne donne pas de détail', () {
      expect(
        sttFailureFromCode(SttErrorCode.unavailable).message,
        contains(SttErrorCode.unavailable),
      );
      expect(
        sttFailureFromCode(SttErrorCode.unavailable, details: '').message,
        contains(SttErrorCode.unavailable),
      );
    });

    test('porte la langue demandée dans la panne de modèle', () {
      final failure =
          sttFailureFromCode(SttErrorCode.modelMissing, languageTag: 'en-US')
              as SttModelMissingFailure;

      expect(failure.languageTag, 'en-US');
      expect(failure.message, contains('en-US'));
    });
  });
}
