import 'package:easy_localization/easy_localization.dart';
import 'package:notalone/core/l10n/l10n_keys.dart';
import 'package:notalone/features/capture/data/background_capture_guard_factory.dart';
import 'package:notalone/features/capture/data/battery_plus_level_source.dart';
import 'package:notalone/features/capture/data/record_mic_datasource.dart';
import 'package:notalone/features/capture/data/silero_vad_service.dart';
import 'package:notalone/features/capture/data/stt_engine_factory.dart';
import 'package:notalone/features/capture/domain/capture_speech_use_case.dart';
import 'package:notalone/features/capture/domain/mic_status_reporter.dart';
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
import 'package:notalone/features/session/data/periodic_mic_status_reporter.dart';
import 'package:notalone/features/session/data/web_socket_guest_client.dart';
import 'package:notalone/features/session/domain/guest_client.dart';
import 'package:notalone/features/session/domain/protocol/session_message.dart';
import 'package:notalone/features/session/domain/supervise_participants_use_case.dart';
import 'package:notalone/features/session/presentation/home_view.dart';
import 'package:notalone/features/session/presentation/home_viewmodel.dart';
import 'package:notalone/features/session/presentation/host_lobby_view.dart';
import 'package:notalone/features/session/presentation/host_lobby_viewmodel.dart';
import 'package:notalone/features/session/presentation/join_view.dart';
import 'package:notalone/features/session/presentation/join_viewmodel.dart';
import 'package:notalone/features/settings/presentation/settings_view.dart';
import 'package:notalone/features/settings/presentation/settings_viewmodel.dart';
import 'package:notalone/features/transcript/data/guest_segment_publisher.dart';
import 'package:notalone/features/transcript/data/host_segment_publisher.dart';
import 'package:notalone/features/transcript/data/host_speaker_directory.dart';
import 'package:notalone/features/transcript/data/host_transcript_binder.dart';
import 'package:notalone/features/transcript/data/shared_preferences_transcript_preferences.dart';
import 'package:notalone/features/transcript/data/wakelock_plus_screen_wake_lock.dart';
import 'package:notalone/features/transcript/domain/merge_transcripts_use_case.dart';
import 'package:notalone/features/transcript/domain/transcript_preferences_repository.dart';
import 'package:notalone/features/transcript/presentation/transcript_viewmodel.dart';

/// Racine de composition : toutes les dépendances (repositories, use cases,
/// ViewModels) sont construites ici puis injectées par constructeur —
/// pas de service locator (cf. cowork/conventions.md §Architecture).
final class AppDependencies {
  AppDependencies();

  final UserProfileRepository _profiles =
      SharedPreferencesUserProfileRepository();

  final PermissionService _permissions = PermissionHandlerService();

  final TranscriptPreferencesRepository _transcriptPreferences =
      SharedPreferencesTranscriptPreferences();

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

  SettingsViewModel createSettingsViewModel() => SettingsViewModel(
    profiles: _profiles,
    // Le même repository que le fil : régler la taille ici ou en lisant écrit
    // la même préférence (MVP-12 l'avait prévu).
    preferences: _transcriptPreferences,
  );

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
        // La capture appartient au ViewModel, pas à l'écran : celui-ci se
        // contente de la montrer (MVP-13).
        captureBuilder: (capture) =>
            CaptureView(viewModel: capture, ownsViewModel: false),
      );
    },
    settings: () => SettingsView(viewModel: createSettingsViewModel()),
    capture: () => CaptureView(viewModel: createCaptureViewModel()),
  );

  /// [publisher] nul : écran « mon micro » ouvert depuis l'accueil, hors
  /// session — on capte et on transcrit, on n'envoie rien, et personne ne
  /// supervise ce micro ([micStatus] nul pour la même raison).
  CaptureViewModel createCaptureViewModel({
    SegmentPublisher? publisher,
    MicStatusReporter? micStatus,
  }) {
    const config = VadConfig();
    return CaptureViewModel(
      publisher: publisher,
      micStatus: micStatus,
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
    // Branchés avant que la session démarre : tous trois s'abonnent au flux
    // d'événements du serveur, ils ne doivent manquer aucune admission — ce
    // sont elles qui déclenchent la synchronisation d'horloge, qui donnent
    // aux bulles leur prénom, et qui peuplent le panneau de supervision.
    final binder = HostTranscriptBinder(
      server: server,
      merge: MergeTranscriptsUseCase(),
    );
    final supervision = SuperviseParticipantsUseCase(server: server);
    // Construit ici et non à l'ouverture de l'écran : `entries` est un flux
    // diffusé sans rejeu, une phrase dite pendant que l'hôte montre encore le
    // QR serait perdue.
    final transcript = TranscriptViewModel(
      binding: binder,
      speakers: HostSpeakerDirectory(server: server),
      preferences: _transcriptPreferences,
      wakeLock: WakelockPlusScreenWakeLock(),
    );
    return HostLobbyViewModel(
      server: server,
      advertiser: BonsoirSessionAdvertiser(),
      supervision: supervision,
      hostName: hostName,
      sessionName: sessionName,
      transcript: transcript,
      // L'hôte capte sa propre voix (doc 02 §1) mais n'a pas de socket vers
      // lui-même : ses segments entrent directement dans la fusion et son état
      // de micro directement dans la supervision. C'est la seule différence
      // avec un invité, et elle tient dans ces deux lignes.
      createHostCapture: (participantId) => createCaptureViewModel(
        publisher: HostSegmentPublisher(
          merge: binder.merge,
          participantId: participantId,
        ),
        micStatus: PeriodicMicStatusReporter(
          battery: const BatteryPlusLevelSource(),
          publish: (state, batteryPct) => supervision.reportLocal(
            participantId: participantId,
            state: state,
            batteryPct: batteryPct,
          ),
        ),
      ),
    );
  }

  JoinViewModel createJoinViewModel({
    required GuestClient client,
    required String initialName,
  }) => JoinViewModel(
    client: client,
    browser: BonsoirSessionBrowser(),
    initialName: initialName,
    createCapture: () => createCaptureViewModel(
      publisher: GuestSegmentPublisher(client: client),
      micStatus: PeriodicMicStatusReporter(
        battery: const BatteryPlusLevelSource(),
        publish: (state, batteryPct) =>
            client.send(MicStatus(state: state, batteryPct: batteryPct)),
      ),
    ),
  );
}
