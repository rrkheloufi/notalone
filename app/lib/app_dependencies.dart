import 'package:notalone/features/capture/data/record_mic_datasource.dart';
import 'package:notalone/features/capture/data/silero_vad_service.dart';
import 'package:notalone/features/capture/domain/vad_config.dart';
import 'package:notalone/features/capture/presentation/vad_debug_viewmodel.dart';

/// Racine de composition : toutes les dépendances (repositories, use cases,
/// ViewModels) sont construites ici puis injectées par constructeur —
/// pas de service locator (cf. cowork/conventions.md §Architecture).
final class AppDependencies {
  const AppDependencies();

  /// Câblage jetable de l'écran de debug du spike MVP-02, remplacé par le
  /// vrai graphe capture/ en MVP-08.
  VadDebugViewModel createVadDebugViewModel() {
    const config = VadConfig();
    return VadDebugViewModel(
      mic: RecordMicDatasource(),
      vad: SileroVadService(config: config),
      config: config,
    );
  }
}
