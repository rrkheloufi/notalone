import 'dart:io';

/// Résolution de l'adresse IPv4 locale à mettre dans le QR code.
/// Préfère les plages privées usuelles (box domestique puis partage de
/// connexion) ; retourne null hors réseau.
abstract final class LocalIp {
  static Future<String?> find() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    );
    final candidates = [
      for (final interface in interfaces)
        for (final address in interface.addresses)
          if (!address.isLoopback && !address.isLinkLocal) address.address,
    ];
    if (candidates.isEmpty) return null;
    for (final prefix in ['192.168.', '10.', '172.']) {
      for (final candidate in candidates) {
        if (candidate.startsWith(prefix)) return candidate;
      }
    }
    return candidates.first;
  }
}
