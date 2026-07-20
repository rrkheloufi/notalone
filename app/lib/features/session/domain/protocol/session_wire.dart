/// Point d'entrée WebSocket de la session : c'est un élément du contrat de fil
/// (cf. cowork/02-architecture.md §4), partagé par les deux bouts — le serveur
/// hôte l'expose, le client invité s'y connecte. Il vit donc en `domain/` et
/// non dans l'une des deux implémentations `data/`.
abstract final class SessionWire {
  static const String scheme = 'ws';

  static const String path = '/ws';

  static Uri uriFor({required String host, required int port}) =>
      Uri(scheme: scheme, host: host, port: port, path: path);
}
