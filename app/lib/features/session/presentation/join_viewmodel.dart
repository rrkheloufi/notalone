import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:notalone/core/command/command.dart';
import 'package:notalone/core/result/result.dart';
import 'package:notalone/features/session/domain/discovered_session.dart';
import 'package:notalone/features/session/domain/guest_client.dart';
import 'package:notalone/features/session/domain/qr_session_payload.dart';
import 'package:notalone/features/session/domain/session_discovery.dart';

/// Étapes du parcours « Rejoindre » (cf. cowork/01-cadrage-produit.md §3) :
/// scanner, confirmer son prénom, être connecté. Le reste ne sont que les
/// aléas du réseau.
enum JoinStep {
  scanning,
  confirmingName,
  connecting,
  connected,
  reconnecting,
  lost,
  ended,
}

/// Parcours d'entrée en session côté invité : scan du QR (ou choix d'une
/// session découverte en mDNS), confirmation du prénom, connexion.
class JoinViewModel extends ChangeNotifier {
  JoinViewModel({
    required this._client,
    required this._browser,
    required String initialName,
  }) : _name = initialName {
    _eventsSubscription = _client.events.listen(_handleEvent);
    _sessionsSubscription = _browser.sessions.listen(_handleDiscovered);
  }

  final GuestClient _client;
  final SessionBrowser _browser;

  late final Command1<void, String> scanCommand = Command1(_scan);
  late final Command1<void, DiscoveredSession> pickCommand = Command1(_pick);
  late final Command1<void, String> joinCommand = Command1(_join);
  late final Command0<void> discoverCommand = Command0(_discover);

  StreamSubscription<GuestClientEvent>? _eventsSubscription;
  StreamSubscription<List<DiscoveredSession>>? _sessionsSubscription;

  JoinStep _step = JoinStep.scanning;
  JoinStep get step => _step;

  String _name;

  /// Prénom proposé puis confirmé par l'invité. MVP-07 le remplacera par le
  /// prénom persisté, sans que ce ViewModel change.
  String get name => _name;

  QrSessionPayload? _pendingSession;

  /// Session visée, connue dès le scan et jusqu'à la sortie.
  QrSessionPayload? get pendingSession => _pendingSession;

  GuestSession? get session => _client.session;

  List<DiscoveredSession> _discoveredSessions = const [];
  List<DiscoveredSession> get discoveredSessions => _discoveredSessions;

  int _reconnectAttempt = 0;

  /// Numéro de la tentative de reconnexion en cours, pour rassurer l'invité
  /// pendant une coupure.
  int get reconnectAttempt => _reconnectAttempt;

  /// Cause de la perte définitive de connexion, en état [JoinStep.lost].
  String? _lostReason;
  String? get lostReason => _lostReason;

  /// Revient au scan : après une session terminée, une connexion perdue, ou
  /// sur décision de l'invité.
  Future<void> backToScanning() async {
    await _client.leave();
    _pendingSession = null;
    _reconnectAttempt = 0;
    _lostReason = null;
    _step = JoinStep.scanning;
    scanCommand.clearResult();
    joinCommand.clearResult();
    notifyListeners();
    await discoverCommand.execute();
  }

  Future<Result<void>> _discover() => _browser.start();

  Future<Result<void>> _scan(String raw) async {
    if (_step != JoinStep.scanning) return const Result.ok(null);
    final decoded = QrSessionPayload.decode(raw);
    switch (decoded) {
      case Err(:final failure):
        return Result.err(failure);
      case Ok(:final value):
        return _prepare(value);
    }
  }

  Future<Result<void>> _pick(DiscoveredSession discovered) async {
    if (_step != JoinStep.scanning) return const Result.ok(null);
    return _prepare(discovered.toQrPayload());
  }

  /// Une session est visée : on arrête de chercher et on demande le prénom.
  Future<Result<void>> _prepare(QrSessionPayload session) async {
    _pendingSession = session;
    _step = JoinStep.confirmingName;
    notifyListeners();
    await _browser.stop();
    return const Result.ok(null);
  }

  Future<Result<void>> _join(String name) async {
    final session = _pendingSession;
    if (session == null || name.trim().isEmpty) {
      return const Result.ok(null);
    }
    _name = name.trim();
    _step = JoinStep.connecting;
    notifyListeners();
    final joined = await _client.join(session: session, name: _name);
    switch (joined) {
      case Err(:final failure):
        _step = JoinStep.confirmingName;
        notifyListeners();
        return Result.err(failure);
      case Ok():
        _step = JoinStep.connected;
        _reconnectAttempt = 0;
        notifyListeners();
        return const Result.ok(null);
    }
  }

  void _handleEvent(GuestClientEvent event) {
    switch (event) {
      case GuestReconnecting(:final attempt):
        _reconnectAttempt = attempt;
        _step = JoinStep.reconnecting;
      case GuestReconnected():
        _reconnectAttempt = 0;
        _step = JoinStep.connected;
      case GuestConnectionLost(:final failure):
        _lostReason = failure.message;
        _step = JoinStep.lost;
      case GuestSessionEnded():
        _step = JoinStep.ended;
      case GuestMessageReceived():
        // Les messages de l'hôte concernent l'horloge (MVP-09) et le
        // transcript (MVP-11), pas cet écran.
        return;
    }
    notifyListeners();
  }

  void _handleDiscovered(List<DiscoveredSession> sessions) {
    _discoveredSessions = sessions;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_eventsSubscription?.cancel());
    unawaited(_sessionsSubscription?.cancel());
    unawaited(_browser.dispose());
    unawaited(_client.dispose());
    scanCommand.dispose();
    pickCommand.dispose();
    joinCommand.dispose();
    discoverCommand.dispose();
    super.dispose();
  }
}
