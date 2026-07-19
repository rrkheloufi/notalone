import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:notalone/core/command/command.dart';
import 'package:notalone/core/result/result.dart';
import 'package:notalone/features/session/domain/lan_server.dart';
import 'package:notalone/features/session/domain/qr_session_payload.dart';

/// Entrée du journal de l'écran hôte ; la vue la traduit en texte.
@immutable
sealed class HostLogEntry {
  const HostLogEntry();
}

final class GuestJoinedEntry extends HostLogEntry {
  const GuestJoinedEntry({required this.clientId});

  final int clientId;
}

final class GuestLeftEntry extends HostLogEntry {
  const GuestLeftEntry({required this.clientId});

  final int clientId;
}

final class GuestMessageEntry extends HostLogEntry {
  const GuestMessageEntry({required this.clientId, required this.text});

  final int clientId;
  final String text;
}

final class HostMessageEntry extends HostLogEntry {
  const HostMessageEntry({required this.text});

  final String text;
}

/// ViewModel de l'écran hôte du spike MVP-03 (jetable, remplacé par le
/// vrai host_lobby en MVP-06).
class LanHostDebugViewModel extends ChangeNotifier {
  LanHostDebugViewModel({
    required this._server,
    this._sessionName = 'NotAlone',
  });

  final LanServer _server;
  final String _sessionName;

  late final Command0<void> startCommand = Command0(_start);
  late final Command0<void> stopCommand = Command0(_stop);
  late final Command1<void, String> sendCommand = Command1(_send);

  QrSessionPayload? _payload;
  bool get isRunning => _payload != null;
  String? get qrData => _payload?.encode();
  String? get host => _payload?.host;
  int? get port => _payload?.port;

  final List<HostLogEntry> _log = [];
  List<HostLogEntry> get log => List.unmodifiable(_log);

  StreamSubscription<LanServerEvent>? _subscription;

  Future<Result<void>> _start() async {
    if (isRunning) return const Result.ok(null);
    final started = await _server.start();
    switch (started) {
      case Err(:final failure):
        return Result.err(failure);
      case Ok(:final value):
        _payload = QrSessionPayload(
          sessionName: _sessionName,
          host: value.host,
          port: value.port,
          token: value.token,
        );
        _log.clear();
        _subscription = _server.events.listen(_handleEvent);
        notifyListeners();
        return const Result.ok(null);
    }
  }

  Future<Result<void>> _stop() async {
    if (!isRunning) return const Result.ok(null);
    await _subscription?.cancel();
    _subscription = null;
    await _server.stop();
    _payload = null;
    notifyListeners();
    return const Result.ok(null);
  }

  Future<Result<void>> _send(String text) async {
    if (!isRunning || text.isEmpty) return const Result.ok(null);
    _server.broadcast(text);
    _log.add(HostMessageEntry(text: text));
    notifyListeners();
    return const Result.ok(null);
  }

  void _handleEvent(LanServerEvent event) {
    _log.add(switch (event) {
      LanClientConnected(:final clientId) => GuestJoinedEntry(
        clientId: clientId,
      ),
      LanClientDisconnected(:final clientId) => GuestLeftEntry(
        clientId: clientId,
      ),
      LanMessageReceived(:final clientId, :final text) => GuestMessageEntry(
        clientId: clientId,
        text: text,
      ),
    });
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    unawaited(_server.stop());
    startCommand.dispose();
    stopCommand.dispose();
    sendCommand.dispose();
    super.dispose();
  }
}
