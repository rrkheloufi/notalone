import 'package:flutter_test/flutter_test.dart';
import 'package:notalone/features/transcript/data/shared_preferences_transcript_preferences.dart';
import 'package:notalone/features/transcript/domain/transcript_text_scale.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SharedPreferencesTranscriptPreferences repository;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    repository = SharedPreferencesTranscriptPreferences();
  });

  test('sans réglage enregistré, rend la taille initiale', () async {
    final read = await repository.readTextScale();

    expect(read.valueOrNull, TranscriptTextScale.initial);
  });

  test('relit la taille écrite', () async {
    await repository.writeTextScale(TranscriptTextScale.maximum);

    final read = await repository.readTextScale();

    expect(read.valueOrNull, TranscriptTextScale.maximum);
  });

  test('stocke le nom de la taille, pas son index', () async {
    await repository.writeTextScale(TranscriptTextScale.large);

    final preferences = await SharedPreferences.getInstance();
    // Intercaler une taille un jour ne doit pas changer le réglage sous le
    // lecteur : c'est le nom qui fait foi.
    expect(
      preferences.getString(
        SharedPreferencesTranscriptPreferences.textScaleKey,
      ),
      TranscriptTextScale.large.name,
    );
  });

  test('une valeur illisible retombe sur la taille initiale', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      SharedPreferencesTranscriptPreferences.textScaleKey: 'gigantesque',
    });

    final read = await repository.readTextScale();

    expect(read.isOk, isTrue);
    expect(read.valueOrNull, TranscriptTextScale.initial);
  });

  test('n’écrit rien d’autre que le réglage d’affichage', () async {
    await repository.writeTextScale(TranscriptTextScale.maximum);

    final preferences = await SharedPreferences.getInstance();
    // Le fil lui-même reste éphémère (CLAUDE.md règle 5).
    expect(preferences.getKeys(), {
      SharedPreferencesTranscriptPreferences.textScaleKey,
    });
  });
}
