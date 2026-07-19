import 'package:meta/meta.dart';
import 'package:notalone/core/result/result.dart';

/// Serveur de session LAN minimal du spike MVP-03 — messages texte bruts,
/// token vérifié à l'upgrade WebSocket. Remplacé par le vrai `HostServer`
/// protocolisé en MVP-05. Le transport est un outil externe : interface en
/// domain, implémentation en data (CLAUDE.md règle 3).
abstract interface class LanServer {
  /// Démarre sur un port éphémère et retourne de quoi construire le QR.
  Future<Result<LanServerInfo>> start();

  Stream<LanServerEvent> get events;

  /// Diffuse un message texte à tous les invités connectés.
  void broadcast(String text);

  Future<void> stop();
}

/// Infos de connexion du serveur démarré (base du payload QR).
@immutable
class LanServerInfo {
  const LanServerInfo({
    required this.host,
    required this.port,
    required this.token,
  });

  final String host;
  final int port;
  final String token;
}

@immutable
sealed class LanServerEvent {
  const LanServerEvent();
}

final class LanClientConnected extends LanServerEvent {
  const LanClientConnected({required this.clientId});

  final int clientId;
}

final class LanClientDisconnected extends LanServerEvent {
  const LanClientDisconnected({required this.clientId});

  final int clientId;
}

final class LanMessageReceived extends LanServerEvent {
  const LanMessageReceived({required this.clientId, required this.text});

  final int clientId;
  final String text;
}
