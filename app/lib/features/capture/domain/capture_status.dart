/// État du micro de cet invité, vu du domaine.
///
/// Volontairement distinct du message protocole `mic_status` : `capture/`
/// n'importe jamais `session/`. La traduction vers le fil (et l'ajout du
/// niveau de batterie) revient à MVP-13, qui possède le panneau de
/// supervision de l'hôte.
enum CaptureStatus {
  /// Capture jamais démarrée, ou arrêtée par l'utilisateur.
  idle,

  /// Le micro tourne et alimente le VAD.
  active,

  /// L'OS a repris le micro (appel entrant, autre app) — cf. doc 03 R5.
  /// La reprise est automatique dès que l'OS rend la main.
  interrupted,

  /// L'invité a coupé son micro lui-même.
  muted,
}
