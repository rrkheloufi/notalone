import 'package:notalone/core/result/result.dart';
import 'package:notalone/features/session/domain/discovered_session.dart';

/// Annonce mDNS de la session côté hôte (`_notalone._tcp`), secours du QR.
/// Un échec n'est jamais bloquant : le QR reste le chemin nominal.
abstract interface class SessionAdvertiser {
  Future<Result<void>> advertise({
    required String sessionName,
    required int port,
    required String token,
  });

  Future<void> stop();
}

/// Recherche des sessions annoncées sur le LAN, côté invité.
abstract interface class SessionBrowser {
  /// Sessions actuellement visibles, réémises à chaque apparition ou
  /// disparition.
  Stream<List<DiscoveredSession>> get sessions;

  Future<Result<void>> start();

  Future<void> stop();

  /// Libère définitivement le navigateur et son flux.
  Future<void> dispose();
}
