import 'package:notalone/core/result/result.dart';
import 'package:notalone/features/transcript/domain/transcript_failure.dart';
import 'package:notalone/features/transcript/domain/transcript_preferences_repository.dart';
import 'package:notalone/features/transcript/domain/transcript_text_scale.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Taille de lecture persistée via `shared_preferences`, comme le prénom
/// (doc 02 §9). Le nom de l'enum est stocké plutôt que son index : renuméroter
/// ou intercaler une taille ne doit pas changer le réglage sous le lecteur.
class SharedPreferencesTranscriptPreferences
    implements TranscriptPreferencesRepository {
  static const String textScaleKey = 'transcript.textScale';

  @override
  Future<Result<TranscriptTextScale>> readTextScale() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      return Result.ok(
        TranscriptTextScale.fromName(preferences.getString(textScaleKey)),
      );
    } on Exception catch (exception) {
      return Result.err(TranscriptPreferencesFailure('$exception'));
    }
  }

  @override
  Future<Result<void>> writeTextScale(TranscriptTextScale scale) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(textScaleKey, scale.name);
      return const Result.ok(null);
    } on Exception catch (exception) {
      return Result.err(TranscriptPreferencesFailure('$exception'));
    }
  }
}
