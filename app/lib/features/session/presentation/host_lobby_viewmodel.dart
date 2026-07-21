import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:notalone/core/command/command.dart';
import 'package:notalone/core/result/result.dart';
import 'package:notalone/features/capture/presentation/capture_viewmodel.dart';
import 'package:notalone/features/session/domain/host_server.dart';
import 'package:notalone/features/session/domain/participant_supervision.dart';
import 'package:notalone/features/session/domain/qr_session_payload.dart';
import 'package:notalone/features/session/domain/session_discovery.dart';
import 'package:notalone/features/session/domain/supervise_participants_use_case.dart';
import 'package:notalone/features/transcript/presentation/transcript_viewmodel.dart';

/// Construit la capture de l'hôte une fois son identité connue : elle ne l'est
/// qu'au retour de `HostServer.start()`, c'est-à-dire après la composition du
/// ViewModel. La fabrique garde donc le câblage dans `app_dependencies.dart`
/// (CLAUDE.md règle 1) sans le faire dépendre d'un identifiant qui n'existe
/// pas encore.
typedef HostCaptureFactory = CaptureViewModel Function(String participantId);

/// Salon de l'hôte : il démarre la session, montre le QR à scanner, voit les
/// convives arriver et **supervise leurs micros** (cf.
/// cowork/01-cadrage-produit.md §3 et §7.5).
class HostLobbyViewModel extends ChangeNotifier {
  HostLobbyViewModel({
    required this._server,
    required this._advertiser,
    required this._supervision,
    required this._hostName,
    required this._sessionName,
    this._transcript,
    this._createHostCapture,
  }) {
    _supervisionSubscription = _supervision.changes.listen(_onSupervision);
  }

  final HostServer _server;
  final SessionAdvertiser _advertiser;
  final SuperviseParticipantsUseCase _supervision;
  final String _hostName;
  final String _sessionName;

  /// Le fil de cette session. Le salon le tient parce qu'il tient la durée de
  /// vie de la session elle-même : le lecteur doit pouvoir revenir au QR puis
  /// rouvrir le fil sans rien perdre, donc ce n'est pas l'écran du fil qui
  /// décide de sa fin. Nul en test, et hors session.
  final TranscriptViewModel? _transcript;

  /// Nulle en test : la capture de l'hôte demande micro, VAD et moteur STT.
  final HostCaptureFactory? _createHostCapture;

  TranscriptViewModel? get transcript => _transcript;

  late final Command0<void> startCommand = Command0(_start);
  late final Command0<void> endSessionCommand = Command0(_endSession);

  StreamSubscription<HostServerEvent>? _eventsSubscription;
  StreamSubscription<List<ParticipantSupervision>>? _supervisionSubscription;

  /// La capture de l'hôte, qui met sa propre voix sur le fil (doc 02 §1).
  /// Nulle tant que la session n'a pas démarré : elle a besoin de l'identité
  /// que le serveur attribue à l'hôte.
  CaptureViewModel? _hostCapture;
  CaptureViewModel? get hostCapture => _hostCapture;

  bool _isRunning = false;
  bool get isRunning => _isRunning;

  bool _isEnded = false;
  bool get isEnded => _isEnded;

  /// Payload encodé à afficher en QR, nul tant que la session n'a pas démarré.
  String? _qrData;
  String? get qrData => _qrData;

  String? _host;
  String? get host => _host;

  int? _port;
  int? get port => _port;

  String get sessionName => _sessionName;

  /// Faux si l'annonce mDNS n'a pas pu démarrer : le QR reste le chemin
  /// nominal, l'écran se contente d'omettre la mention du secours.
  bool _isDiscoverable = false;
  bool get isDiscoverable => _isDiscoverable;

  /// Les convives, hôte compris, avec l'état de leur micro. Remplace la liste
  /// de `Participant` brute de MVP-06 : le salon n'a jamais eu besoin de
  /// l'identité seule, il a besoin de savoir qui va bien.
  List<ParticipantSupervision> get participants => _supervision.participants;

  /// Ceux qui demandent quelque chose à l'hôte, pour le bandeau du fil.
  List<ParticipantSupervision> get alerts => _supervision.alerting;

  bool get hasAlerts => _supervision.hasAlerts;

  /// Dernier refus signalé par le serveur (session complète, QR périmé) :
  /// l'hôte est le seul à pouvoir comprendre pourquoi un convive n'entre pas.
  String? _lastRejection;
  String? get lastRejection => _lastRejection;

  void clearRejection() {
    _lastRejection = null;
    notifyListeners();
  }

  Future<Result<void>> _start() async {
    if (_isRunning) return const Result.ok(null);
    final started = await _server.start(hostName: _hostName);
    switch (started) {
      case Err(:final failure):
        return Result.err(failure);
      case Ok(value: final info):
        _host = info.host;
        _port = info.port;
        _qrData = QrSessionPayload(
          sessionName: _sessionName,
          host: info.host,
          port: info.port,
          token: info.token,
        ).encode();
        _isRunning = true;
        _eventsSubscription = _server.events.listen(_handleEvent);
        // `registerHost` n'émet pas d'événement : sans ce rappel, la propre
        // ligne de l'hôte n'apparaîtrait qu'à l'arrivée du premier invité.
        _supervision.refresh();
        _startHostCapture(info.hostParticipant.id);
        notifyListeners();
        // Le mDNS n'est qu'un secours : son échec ne compromet pas la session.
        final advertised = await _advertiser.advertise(
          sessionName: _sessionName,
          port: info.port,
          token: info.token,
        );
        _isDiscoverable = advertised.isOk;
        notifyListeners();
        return const Result.ok(null);
    }
  }

  /// L'hôte capte dès que la session est ouverte, sans écran de capture : il
  /// passe le repas sur le fil, pas sur un moniteur de micro. Un échec (micro
  /// refusé — la home l'accepte, décision Rayan MVP-07) ne compromet rien :
  /// il reste le lecteur, sa ligne de supervision dira simplement que son
  /// micro ne tourne pas.
  void _startHostCapture(String participantId) {
    final capture = _createHostCapture?.call(participantId);
    if (capture == null) return;
    _hostCapture = capture;
    capture.addListener(notifyListeners);
    unawaited(capture.startCommand.execute());
  }

  void _handleEvent(HostServerEvent event) {
    switch (event) {
      case ParticipantJoined() || ParticipantDisconnected():
        // La liste vient de la supervision, qui écoute le même flux : il n'y a
        // rien à recopier ici, seulement à redessiner.
        break;
      case ParticipantRejected(:final reason):
        _lastRejection = reason;
      case SessionMessageReceived():
        // Les messages applicatifs vont au transcript et à la supervision, qui
        // écoutent le même flux : le salon n'a rien à en faire.
        return;
    }
    notifyListeners();
  }

  void _onSupervision(List<ParticipantSupervision> _) => notifyListeners();

  /// Fin de session : `session_end` part vers tous les invités, puis **tout
  /// est effacé de ce téléphone** — le fil, les participants, ce que le micro
  /// de l'hôte avait entendu. Rien ne survit à cet appel (CLAUDE.md règle 5,
  /// critère d'acceptation MVP-13).
  Future<Result<void>> _endSession() async {
    if (!_isRunning || _isEnded) return const Result.ok(null);
    // La session est déclarée finie **d'abord** : l'écran bascule sur la
    // confirmation d'effacement sans attendre que les flux se démontent, ce
    // qui prend un tour de boucle d'événements. Un lecteur qui vient
    // d'appuyer ne doit pas voir le QR une fraction de seconde de plus.
    _isEnded = true;
    _isRunning = false;
    _isDiscoverable = false;
    notifyListeners();
    await _advertiser.stop();
    await _releaseHostCapture();
    // Seul appel réellement attendu : c'est lui qui diffuse `session_end` aux
    // invités, donc qui déclenche l'effacement sur leurs téléphones.
    await _server.endSession();
    unawaited(_supervision.dispose());
    _transcript?.dispose();
    return const Result.ok(null);
  }

  Future<void> _releaseHostCapture() async {
    final capture = _hostCapture;
    if (capture == null) return;
    capture.removeListener(notifyListeners);
    _hostCapture = null;
    // `endSession` avant `dispose` : le micro s'arrête et les segments encore
    // affichés sont effacés, sans attendre la destruction de l'objet.
    await capture.endSession();
    capture.dispose();
  }

  @override
  void dispose() {
    unawaited(_eventsSubscription?.cancel());
    unawaited(_supervisionSubscription?.cancel());
    unawaited(_advertiser.stop());
    if (!_isEnded) {
      unawaited(_releaseHostCapture());
      unawaited(_server.endSession());
      unawaited(_supervision.dispose());
      _transcript?.dispose();
    }
    startCommand.dispose();
    endSessionCommand.dispose();
    super.dispose();
  }
}
