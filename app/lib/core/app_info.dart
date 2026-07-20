/// Identité de la build, transmise à l'hôte dans le `join_request` pour
/// diagnostiquer une session où tout le monde n'a pas la même version.
/// Maintenue à la main en miroir de `pubspec.yaml` : lire la vraie version
/// demanderait un plugin natif pour une information purement indicative.
abstract final class AppInfo {
  static const String version = '0.1.0';
}
