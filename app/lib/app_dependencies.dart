import 'package:easy_localization/easy_localization.dart';
import 'package:notalone/core/l10n/l10n_keys.dart';
import 'package:notalone/features/capture/data/background_capture_guard_factory.dart';
import 'package:notalone/features/capture/data/record_mic_datasource.dart';
import 'package:notalone/features/capture/data/silero_vad_service.dart';
import 'package:notalone/features/capture/data/stt_engine_factory.dart';
import 'package:notalone/features/capture/domain/capture_speech_use_case.dart';
import 'package:notalone/features/capture/domain/segment_publisher.dart';
import 'package:notalone/features/capture/domain/transcribe_segments_use_case.dart';
import 'package:notalone/features/capture/domain/vad_config.dart';
import 'package:notalone/features/capture/presentation/capture_view.dart';
import 'package:notalone/features/capture/presentation/capture_viewmodel.dart';
import 'package:notalone/features/onboarding/data/permission_handler_service.dart';
import 'package:notalone/features/onboarding/data/shared_preferences_user_profile_repository.dart';
import 'package:notalone/features/onboarding/domain/permission_service.dart';
import 'package:notalone/features/onboarding/domain/user_profile_repository.dart';
import 'package:notalone/features/onboarding/presentation/app_root_viewmodel.dart';
import 'package:notalone/features/onboarding/presentation/onboarding_viewmodel.dart';
import 'package:notalone/features/onboarding/presentation/permission_gate.dart';
import 'package:notalone/features/session/data/bonsoir_session_discovery.dart';
import 'package:notalone/features/session/data/dart_io_host_server.dart';
import 'package:notalone/features/session/data/web_socket_guest_client.dart';
import 'package:notalone/features/session/domain/guest_client.dart';
import 'package:notalone/features/session/presentation/home_view.dart';
import 'package:notalone/features/session/presentation/home_viewmodel.dart';
import 'package:notalone/features/session/presentation/host_lobby_view.dart';
import 'package:notalone/features/session/presentation/host_lobby_viewmodel.dart';
import 'package:notalone/features/session/presentation/join_view.dart';
import 'package:notalone/features/session/presentation/join_viewmodel.dart';
import 'package:notalone/features/settings/presentation/settings_view.dart';
import 'package:notalone/features/settings/presentation/settings_viewmodel.dart';
import 'package:notalone/features/transcript/data/guest_segment_publisher.dart';
import 'package:notalone/features/transcript/data/host_transcript_binder.dart';
import 'package:notalone/features/transcript/domain/merge_transcripts_use_case.dart';

/// Racine de composition : toutes les dépendances (repositories, use cases,
/// ViewModels) sont construites ici puis injectées par constructeur —
/// pas de service locator (cf. cowork/conventions.md §Architecture).
final class AppDependencies {
  AppDependencies();

  final UserProfileRepository _profiles =
      SharedPreferencesUserProfileRepository();

  final PermissionService _permissions = PermissionHandlerService();

  late final PermissionGate microphoneGate = permissionGate(
    service: _permissions,
    permission: AppPermission.microphone,
  );

  late final PermissionGate cameraGate = permissionGate(
    service: _permissions,
    permission: AppPermission.camera,
  );

  AppRootViewModel createAppRootViewModel() =>
      AppRootViewModel(profiles: _profiles);

  OnboardingViewModel createOnboardingViewModel() =>
      OnboardingViewModel(profiles: _profiles);

  HomeViewModel createHomeViewModel({required String name}) =>
      HomeViewModel(profiles: _profiles, name: name);

  SettingsViewModel createSettingsViewModel() =>
      SettingsViewModel(profiles: _profiles);

  late final HomeDestinations homeDestinations = HomeDestinations(
    hostLobby: (name) => HostLobbyView(
      viewModel: createHostLobbyViewModel(
        hostName: name,
        sessionName: L10nKeys.hostLobbySessionName.tr(
          namedArgs: {'name': name},
        ),
      ),
    ),
    join: ({required name, required withScanner}) {
      // Un seul client pour les deux écrans du parcours invité : celui qui
      // tient la session est celui qui met les segments sur le fil.
      final client = WebSocketGuestClient();
      return JoinView(
        viewModel: createJoinViewModel(client: client, initialName: name),
        showScanner: withScanner,
        microphoneGate: microphoneGate,
        captureBuilder: () => CaptureView(
          viewModel: createCaptureViewModel(
            publisher: GuestSegmentPublisher(client: client),
          ),
        ),
      );
    },
    settings: () => SettingsView(viewModel: createSettingsViewModel()),
    capture: () => CaptureView(viewModel: createCaptureViewModel()),
  );

  /// [publisher] nul : écran « mon micro » ouvert depuis l'accueil, hors
  /// session — on capte et on transcrit, on n'envoie rien.
  CaptureViewModel createCaptureViewModel({SegmentPublisher? publisher}) {
    const config = VadConfig();
    return CaptureViewModel(
      publisher: publisher,
      capture: CaptureSpeechUseCase(
        mic: RecordMicDatasource(),
        vad: SileroVadService(config: config),
        guard: createBackgroundCaptureGuard(
          notificationTitle: L10nKeys.appTitle.tr(),
          notificationText: L10nKeys.captureStatusActive.tr(),
        ),
      ),
      transcribe: TranscribeSegmentsUseCase(engine: createSttEngine()),
    );
  }

  HostLobbyViewModel createHostLobbyViewModel({
    required String hostName,
    required String sessionName,
  }) {
    final server = DartIoHostServer();
    // Branché avant que la session démarre : le binder s'abonne au flux
    // d'événements du serveur, il ne doit manquer aucune admission — ce sont
    // elles qui déclenchent la synchronisation d'horloge.
    final transcript = HostTranscriptBinder(
      server: server,
      merge: MergeTranscriptsUseCase(),
    );
    return HostLobbyViewModel(
      server: server,
      advertiser: BonsoirSessionAdvertiser(),
      hostName: hostName,
      sessionName: sessionName,
      transcript: transcript,
    );
  }

  JoinViewModel createJoinViewModel({
    required GuestClient client,
    required String initialName,
  }) => JoinViewModel(
    client: client,
    browser: BonsoirSessionBrowser(),
    initialName: initialName,
  );
}
