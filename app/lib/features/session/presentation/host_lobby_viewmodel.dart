import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:notalone/core/command/command.dart';
import 'package:notalone/core/result/result.dart';
import 'package:notalone/features/session/domain/host_server.dart';
import 'package:notalone/features/session/domain/participant.dart';
import 'package:notalone/features/session/domain/qr_session_payload.dart';
import 'package:notalone/features/session/domain/session_discovery.dart';
import 'package:notalone/features/transcript/domain/transcript_binding.dart';

/// Salon de l'hôte : il démarre la session, montre le QR à scanner et voit
/// les convives arriver (cf. cowork/01-cadrage-produit.md §3).
class HostLobbyViewModel extends ChangeNotifier {
  HostLobbyViewModel({
    required this._server,
    required this._advertiser,
    required this._hostName,
    required this._sessionName,
    this._transcript,
  });

  final HostServer _server;
  final SessionAdvertiser _advertiser;
  final String _hostName;
  final String _sessionName;

  /// La fusion branchée sur cette session. Le salon la tient parce qu'il tient
  /// la durée de vie de la session elle-même ; MVP-12 la lui reprendra en même
  /// temps qu'il prendra l'écran du fil. Nulle en test, et hors session.
  final TranscriptBinding? _transcript;

  late final Command0<void> startCommand = Command0(_start);
  late final Command0<void> endSessionCommand = Command0(_endSession);

  StreamSubscription<HostServerEvent>? _eventsSubscription;

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

  List<Participant> _participants = const [];
  List<Participant> get participants => _participants;

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
        _participants = _server.participants;
        _eventsSubscription = _server.events.listen(_handleEvent);
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

  void _handleEvent(HostServerEvent event) {
    switch (event) {
      case ParticipantJoined() || ParticipantDisconnected():
        _participants = _server.participants;
      case ParticipantRejected(:final reason):
        _lastRejection = reason;
      case SessionMessageReceived():
        // Les messages applicatifs vont au transcript, qui écoute le même flux
        // d'événements (`HostTranscriptBinder`) : le salon n'a rien à en faire.
        return;
    }
    notifyListeners();
  }

  Future<Result<void>> _endSession() async {
    if (!_isRunning || _isEnded) return const Result.ok(null);
    await _advertiser.stop();
    await _server.endSession();
    await _transcript?.dispose();
    _isEnded = true;
    _isRunning = false;
    _isDiscoverable = false;
    _participants = const [];
    notifyListeners();
    return const Result.ok(null);
  }

  @override
  void dispose() {
    unawaited(_eventsSubscription?.cancel());
    unawaited(_advertiser.stop());
    if (!_isEnded) {
      unawaited(_server.endSession());
      unawaited(_transcript?.dispose());
    }
    startCommand.dispose();
    endSessionCommand.dispose();
    super.dispose();
  }
}
