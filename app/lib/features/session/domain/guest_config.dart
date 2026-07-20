import 'package:meta/meta.dart';

/// Constantes de cycle de vie du client invité (cf. cowork/02-architecture.md
/// §4). Injectable pour rejouer le backoff en millisecondes dans les tests,
/// comme `SessionConfig` côté hôte (cf. cowork/conventions.md §Style).
@immutable
class GuestConfig {
  const GuestConfig({
    this.connectTimeout = const Duration(seconds: 5),
    this.joinAckTimeout = const Duration(seconds: 5),
    this.reconnectBackoff = defaultReconnectBackoff,
    this.maxQueuedMessages = 200,
  });

  /// Doc 02 §4 fixe 1/2/4 s ; les essais suivants restent à 4 s et la série
  /// s'arrête après ~21 s (décision Rayan, 20/07/2026). Une coupure WiFi de
  /// quelques secondes est donc absorbée sans que l'app s'acharne quand
  /// l'hôte, lui, a définitivement éteint la session.
  static const List<Duration> defaultReconnectBackoff = [
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 4),
    Duration(seconds: 4),
    Duration(seconds: 4),
    Duration(seconds: 4),
  ];

  /// Délai d'ouverture du socket TCP/WebSocket.
  final Duration connectTimeout;

  /// Délai laissé à l'hôte pour répondre au `join_request`.
  final Duration joinAckTimeout;

  /// Attentes successives entre deux tentatives de reconnexion. Sa longueur
  /// est le nombre d'essais avant abandon.
  final List<Duration> reconnectBackoff;

  /// Taille de la file d'envoi pendant une coupure. Au-delà, le plus ancien
  /// message est jeté : sur une reprise tardive, les segments de parole les
  /// plus frais valent mieux que ceux d'il y a une minute.
  final int maxQueuedMessages;
}
