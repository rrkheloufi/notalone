import 'dart:async';

import 'package:bonsoir/bonsoir.dart';
import 'package:notalone/core/result/result.dart';
import 'package:notalone/features/session/domain/discovered_session.dart';
import 'package:notalone/features/session/domain/session_discovery.dart';
import 'package:notalone/features/session/domain/session_failure.dart';

/// Annonce `_notalone._tcp` de l'hôte (cf. cowork/02-architecture.md §4).
///
/// Le package `bonsoir` remplace le `nsd`/`multicast_dns` pressenti au doc 02
/// §9 : `multicast_dns` ne sait que découvrir, pas annoncer, et ne peut donc
/// pas servir côté hôte (décision Rayan, 20/07/2026).
class BonsoirSessionAdvertiser implements SessionAdvertiser {
  BonsoirBroadcast? _broadcast;

  @override
  Future<Result<void>> advertise({
    required String sessionName,
    required int port,
    required String token,
  }) async {
    await stop();
    try {
      final broadcast = BonsoirBroadcast(
        service: BonsoirService(
          name: sessionName,
          type: DiscoveredSession.serviceType,
          port: port,
          attributes: DiscoveredSession.attributesFor(
            sessionName: sessionName,
            token: token,
          ),
        ),
      );
      await broadcast.initialize();
      await broadcast.start();
      _broadcast = broadcast;
      return const Result.ok(null);
    } on Exception catch (exception) {
      return Result.err(DiscoveryUnavailableFailure('$exception'));
    }
  }

  @override
  Future<void> stop() async {
    final broadcast = _broadcast;
    _broadcast = null;
    if (broadcast == null || broadcast.isStopped) return;
    try {
      await broadcast.stop();
    } on Exception {
      return; // Arrêt best-effort : l'annonce expire d'elle-même côté réseau.
    }
  }
}

/// Découverte des sessions annoncées sur le LAN, côté invité. Une annonce
/// n'est retenue qu'une fois **résolue** (adresse et TXT record connus) et
/// exploitable : la liste exposée ne contient que des sessions joignables.
class BonsoirSessionBrowser implements SessionBrowser {
  BonsoirDiscovery? _discovery;
  StreamSubscription<BonsoirDiscoveryEvent>? _subscription;

  final StreamController<List<DiscoveredSession>> _sessions =
      StreamController<List<DiscoveredSession>>.broadcast();

  /// Sessions résolues, indexées par nom de service mDNS — c'est lui que
  /// portent les événements de perte.
  final Map<String, DiscoveredSession> _found = {};

  @override
  Stream<List<DiscoveredSession>> get sessions => _sessions.stream;

  @override
  Future<Result<void>> start() async {
    if (_discovery != null) return const Result.ok(null);
    try {
      final discovery = BonsoirDiscovery(
        type: DiscoveredSession.serviceType,
      );
      await discovery.initialize();
      // Renseigné avant l'abonnement : le premier événement peut arriver
      // pendant `start()` et la résolution a besoin du résolveur.
      _discovery = discovery;
      _subscription = discovery.eventStream?.listen(_handleEvent);
      await discovery.start();
      return const Result.ok(null);
    } on Exception catch (exception) {
      return Result.err(DiscoveryUnavailableFailure('$exception'));
    }
  }

  @override
  Future<void> stop() async {
    final discovery = _discovery;
    _discovery = null;
    await _subscription?.cancel();
    _subscription = null;
    _found.clear();
    if (discovery == null || discovery.isStopped) return;
    try {
      await discovery.stop();
    } on Exception {
      return;
    }
  }

  void _handleEvent(BonsoirDiscoveryEvent event) {
    switch (event) {
      case BonsoirDiscoveryServiceFoundEvent(:final service):
        // Une annonce trouvée n'a encore ni adresse ni TXT record : c'est la
        // résolution qui les apporte.
        final resolver = _discovery?.serviceResolver;
        if (resolver != null) unawaited(service.resolve(resolver));
      case BonsoirDiscoveryServiceResolvedEvent(:final service) ||
          BonsoirDiscoveryServiceUpdatedEvent(:final service):
        final decoded = DiscoveredSession.fromAdvertisement(
          attributes: service.attributes,
          host: service.hostAddress,
          port: service.port,
          fallbackName: service.name,
        );
        // Annonce inexploitable (autre app, version incompatible) : ignorée.
        if (decoded case Ok(value: final session)) {
          _found[service.name] = session;
          _publish();
        }
      case BonsoirDiscoveryServiceLostEvent(:final service):
        if (_found.remove(service.name) != null) _publish();
      case BonsoirDiscoveryStartedEvent() ||
          BonsoirDiscoveryStoppedEvent() ||
          BonsoirDiscoveryServiceResolveFailedEvent() ||
          BonsoirDiscoveryUnknownEvent():
        return;
    }
  }

  void _publish() {
    if (!_sessions.isClosed) _sessions.add(List.unmodifiable(_found.values));
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _sessions.close();
  }
}
