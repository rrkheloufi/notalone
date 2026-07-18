/// Erreur métier typée. Chaque feature définit ses propres sous-classes ;
/// aucune exception ne traverse la couche data (cf. cowork/conventions.md).
abstract class Failure {
  const Failure(this.message);

  final String message;

  @override
  String toString() => message;
}
