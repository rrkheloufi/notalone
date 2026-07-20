import 'package:notalone/features/capture/data/record_mic_datasource.dart';
import 'package:notalone/features/capture/data/silero_vad_service.dart';
import 'package:notalone/features/capture/domain/vad_config.dart';
import 'package:notalone/features/capture/presentation/vad_debug_viewmodel.dart';
import 'package:notalone/features/session/data/bonsoir_session_discovery.dart';
import 'package:notalone/features/session/data/dart_io_host_server.dart';
import 'package:notalone/features/session/data/web_socket_guest_client.dart';
import 'package:notalone/features/session/presentation/host_lobby_viewmodel.dart';
import 'package:notalone/features/session/presentation/join_viewmodel.dart';

/// Racine de composition : toutes les dépendances (repositories, use cases,
/// ViewModels) sont construites ici puis injectées par constructeur —
/// pas de service locator (cf. cowork/conventions.md §Architecture).
final class AppDependencies {
  const AppDependencies();

  /// Prénom provisoire tant que MVP-07 n'a pas d'écran d'onboarding ni de
  /// persistance : les deux parcours le proposent dans un champ modifiable,
  /// MVP-07 n'aura qu'à remplacer cette valeur par le prénom persisté.
  static const String provisionalName = 'Invité';

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

  HostLobbyViewModel createHostLobbyViewModel({
    required String hostName,
    required String sessionName,
  }) => HostLobbyViewModel(
    server: DartIoHostServer(),
    advertiser: BonsoirSessionAdvertiser(),
    hostName: hostName,
    sessionName: sessionName,
  );

  JoinViewModel createJoinViewModel({required String initialName}) =>
      JoinViewModel(
        client: WebSocketGuestClient(),
        browser: BonsoirSessionBrowser(),
        initialName: initialName,
      );
}
