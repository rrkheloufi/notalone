# Conventions de développement

> Règles d'or du projet. `/dev-task` les applique systématiquement. Toute dérogation se discute avec Rayan avant de coder.

## Architecture (rappel — détail dans 02-architecture.md §6)

1. MVVM avec **ChangeNotifier natif Flutter**. Interdits : Riverpod, provider, bloc, get_it ou tout autre package de state management / DI.
2. Vues = widgets purs : aucune logique, aucun accès réseau/plateforme, elles écoutent le ViewModel via `ListenableBuilder` et déclenchent des **Commands**.
3. ViewModels : étendent `ChangeNotifier`, zéro import de widgets, dépendances (use cases) injectées par constructeur. Actions exposées en `Command` (pattern du guide officiel Flutter : états running/completed/error observables).
4. `domain/` : pur Dart, zéro import Flutter. C'est là que vit toute la logique métier.
5. Tout outil externe (STT, VAD, transport, stockage, LLM) est derrière une interface de `domain/`. On doit pouvoir changer de fournisseur en ne touchant que `data/` + la racine de composition.
6. Erreurs : `Result<T>` avec `Failure` typées. Les exceptions ne traversent jamais la couche data.
7. DI manuelle : tout se compose dans `app_dependencies.dart`. Pas de singleton global, pas de service locator.

## Style de code

- `very_good_analysis` activé ; `flutter analyze` doit rendre **0 warning** avant tout commit.
- Immutabilité par défaut (`final`, collections non modifiables exposées).
- Nommage : `XxxView`, `XxxViewModel`, `XxxUseCase`, `XxxRepository` (interface) / `XxxRepositoryImpl`, DTOs en `XxxDto`. Fichiers en `snake_case` alignés sur la classe.
- Pas de commentaire qui paraphrase le code ; commenter le *pourquoi* (seuils, workarounds plateformes) avec référence au doc de cadrage (ex. `// cf. cowork/02-architecture.md §5`).
- Constantes métier (seuils VAD, dédup, timeouts) : jamais en dur dans la logique — regroupées dans des objets de config testables (`DedupConfig`, `VadConfig`).
- Chaînes UI : centralisées dès le MVP (fichier de strings FR) pour préparer la localisation v1.

## Tests

- Tout `domain/` est testé (use cases, protocole, dédup : ≥ 90 %). Un bug corrigé = un test de non-régression ajouté.
- ViewModels testés sans widget (instancier, exécuter les commands, vérifier l'état).
- Widget tests pour chaque vue principale ; golden tests pour transcript_view (tailles XL).
- Fixtures : segments de parole synthétiques dans `test/fixtures/` (scénarios cross-talk scriptés).
- Commande unique : `flutter test` doit passer intégralement avant tout commit.

## Git

- Branche `main` toujours verte (analyze + tests).
- Commits : [Conventional Commits](https://www.conventionalcommits.org/) en anglais — `feat(scope): ...`, `fix(scope): ...`, `test:`, `docs:`, `chore:`. Scopes = features (`session`, `capture`, `transcript`, `onboarding`, `settings`, `core`).
- Un commit = une tâche `/dev-task` (ou une sous-étape cohérente). Jamais de code non testé dans un commit `feat`.
- Aucun secret dans le dépôt (clé API Gladia → variable d'environnement / `--dart-define`, jamais commitée).

## Workflow de développement

- Chaque tâche passe par `/dev-task <ID>` (cf. `.claude/commands/dev-task.md`).
- Les fichiers `cowork/tasks/*.md` sont la **source de vérité** de l'avancement : statuts mis à jour à chaque tâche terminée (`⬜ à faire` → `🟧 en cours` → `✅ fait`), section « Réalisé » complétée.
- Toute décision prise en cours de développement qui dévie du cadrage est notée dans la tâche concernée ET signalée à Rayan.
- Les tâches marquées « Manuel (Rayan) » ne sont jamais exécutées par l'IA : elles sont listées en fin de tâche comme actions à faire par Rayan.
