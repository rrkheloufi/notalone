import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:notalone/core/command/command.dart';
import 'package:notalone/core/result/result.dart';
import 'package:notalone/features/session/domain/lan_client.dart';
import 'package:notalone/features/session/domain/qr_session_payload.dart';
import 'package:notalone/features/session/domain/session_failure.dart';

enum GuestConnectionState { scanning, connected, disconnected }

/// ViewModel de l'écran invité du spike MVP-03 (jetable, remplacé par le
/// vrai parcours join en MVP-06).
class LanGuestDebugViewModel extends ChangeNotifier {
  LanGuestDebugViewModel({required this._client}) {
    _messagesSubscription = _client.messages.listen(_handleMessage);
    _disconnectionsSubscription = _client.disconnections.listen(
      (_) => _handleDisconnected(),
    );
  }

  final LanClient _client;

  late final Command1<void, String> scanCommand = Command1(_scan);
  late final Command0<void> measureRttCommand = Command0(_measureRtt);
  late final Command1<void, String> sendCommand = Command1(_send);

  GuestConnectionState _state = GuestConnectionState.scanning;
  GuestConnectionState get state => _state;

  /// Fil de messages : `own` = envoyé par cet invité.
  final List<({bool own, String text})> _messages = [];
  List<({bool own, String text})> get messages => List.unmodifiable(_messages);

  Duration? _medianRtt;
  Duration? get medianRtt => _medianRtt;

  static const int _pingCount = 5;

  StreamSubscription<String>? _messagesSubscription;
  StreamSubscription<void>? _disconnectionsSubscription;

  /// Relance un scan après une déconnexion.
  void resetToScan() {
    _state = GuestConnectionState.scanning;
    _messages.clear();
    _medianRtt = null;
    notifyListeners();
  }

  Future<Result<void>> _scan(String raw) async {
    if (_state != GuestConnectionState.scanning) return const Result.ok(null);
    final decoded = QrSessionPayload.decode(raw);
    switch (decoded) {
      case Err(:final failure):
        return Result.err(failure);
      case Ok(:final value):
        final connected = await _client.connect(value);
        if (connected case Err(:final failure)) return Result.err(failure);
        _state = GuestConnectionState.connected;
        notifyListeners();
        unawaited(measureRttCommand.execute());
        return const Result.ok(null);
    }
  }

  Future<Result<void>> _measureRtt() async {
    final rtts = <Duration>[];
    for (var i = 0; i < _pingCount; i++) {
      final rtt = await _client.ping();
      if (rtt case Ok(:final value)) rtts.add(value);
    }
    if (rtts.isEmpty) {
      return const Result.err(ConnectionFailure('aucun pong reçu'));
    }
    rtts.sort();
    _medianRtt = rtts[rtts.length ~/ 2];
    notifyListeners();
    return const Result.ok(null);
  }

  Future<Result<void>> _send(String text) async {
    if (_state != GuestConnectionState.connected || text.isEmpty) {
      return const Result.ok(null);
    }
    _client.send(text);
    _messages.add((own: true, text: text));
    notifyListeners();
    return const Result.ok(null);
  }

  void _handleMessage(String text) {
    _messages.add((own: false, text: text));
    notifyListeners();
  }

  void _handleDisconnected() {
    if (_state != GuestConnectionState.connected) return;
    _state = GuestConnectionState.disconnected;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_messagesSubscription?.cancel());
    unawaited(_disconnectionsSubscription?.cancel());
    unawaited(_client.disconnect());
    scanCommand.dispose();
    measureRttCommand.dispose();
    sendCommand.dispose();
    super.dispose();
  }
}
