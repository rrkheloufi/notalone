import 'package:meta/meta.dart';
import 'package:notalone/core/result/result.dart';
import 'package:notalone/features/session/domain/qr_session_payload.dart';
import 'package:notalone/features/session/domain/session_failure.dart';

/// Session trouvée par annonce mDNS `_notalone._tcp`, secours du QR quand le
/// scan échoue (cf. cowork/02-architecture.md §4).
///
/// L'annonce porte le **token** dans son enregistrement TXT (décision Rayan,
/// 20/07/2026) : sans lui, un invité qui découvre la session resterait à la
/// porte et le secours ne dépannerait personne. Le LAN est déjà la frontière
/// de confiance du produit — aucune donnée ne le quitte (CLAUDE.md règle 2) —
/// et l'hôte voit arriver chaque invité dans son lobby.
@immutable
class DiscoveredSession {
  const DiscoveredSession({
    required this.sessionName,
    required this.host,
    required this.port,
    required this.token,
  });

  /// Type de service annoncé et recherché sur le LAN.
  static const String serviceType = '_notalone._tcp';

  /// Version du contenu de l'enregistrement TXT, indépendante de celle du
  /// protocole WebSocket : les deux évoluent séparément.
  static const int recordVersion = 1;

  /// Clés du TXT record. RFC 6763 §6 recommande 9 caractères au plus, d'où
  /// les noms courts (`name` plutôt que `sessionName`).
  static const String _versionKey = 'v';
  static const String _nameKey = 'name';
  static const String _tokenKey = 'token';

  final String sessionName;
  final String host;
  final int port;
  final String token;

  /// Contenu du TXT record à annoncer côté hôte. Le nom de session y est
  /// répété car le nom de service mDNS peut être renommé par l'OS en cas de
  /// conflit sur le réseau.
  static Map<String, String> attributesFor({
    required String sessionName,
    required String token,
  }) => {
    _versionKey: '$recordVersion',
    _nameKey: sessionName,
    _tokenKey: token,
  };

  /// Reconstruit une session à partir d'une annonce résolue. Tolérance
  /// ascendante comme le reste du protocole : champs inconnus ignorés,
  /// version supérieure acceptée tant que les champs requis sont là.
  static Result<DiscoveredSession> fromAdvertisement({
    required Map<String, String> attributes,
    required String? host,
    required int port,
    required String fallbackName,
  }) {
    final version = int.tryParse(attributes[_versionKey] ?? '');
    if (version == null || version < 1) {
      return const Result.err(
        DiscoveryRecordMalformedFailure('version absente'),
      );
    }
    final token = attributes[_tokenKey];
    if (token == null || token.isEmpty) {
      return const Result.err(DiscoveryRecordMalformedFailure('token absent'));
    }
    if (host == null || host.isEmpty) {
      return const Result.err(
        DiscoveryRecordMalformedFailure('hôte non résolu'),
      );
    }
    if (port < 1 || port > 65535) {
      return const Result.err(DiscoveryRecordMalformedFailure('port invalide'));
    }
    final name = attributes[_nameKey];
    return Result.ok(
      DiscoveredSession(
        sessionName: name == null || name.isEmpty ? fallbackName : name,
        host: host,
        port: port,
        token: token,
      ),
    );
  }

  /// Ramène la session découverte au même payload que le QR : à partir de là,
  /// le parcours d'entrée est strictement identique dans les deux cas.
  QrSessionPayload toQrPayload() => QrSessionPayload(
    sessionName: sessionName,
    host: host,
    port: port,
    token: token,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DiscoveredSession &&
          other.sessionName == sessionName &&
          other.host == host &&
          other.port == port &&
          other.token == token);

  @override
  int get hashCode => Object.hash(sessionName, host, port, token);
}
