---
description: Développer une tâche du projet NotAlone (charge le contexte, valide, code, teste, résume, propose un commit)
argument-hint: <ID de tâche, ex. MVP-04 ou V1-02>
---

Tu vas développer la tâche **$ARGUMENTS** du projet NotAlone. Suis rigoureusement ce processus, étape par étape, sans en sauter aucune.

## 1. Charger le contexte

- Lis `CLAUDE.md`, `cowork/conventions.md`, et la section de la tâche $ARGUMENTS dans `cowork/tasks/tasks-mvp.md` ou `cowork/tasks/tasks-v1.md`.
- Lis les sections des documents `cowork/01-cadrage-produit.md`, `cowork/02-architecture.md`, `cowork/03-risques-rgpd-roadmap.md` pertinentes pour cette tâche (le doc 02 est requis pour toute tâche touchant pipeline, protocole ou structure).
- Explore le code existant concerné par la tâche avant d'écrire quoi que ce soit.

Si la tâche $ARGUMENTS n'existe pas, liste les IDs disponibles avec leurs statuts et arrête-toi.

## 2. Vérifier les prérequis

- Vérifie que toutes les dépendances de la tâche sont ✅ dans les fichiers de tâches. Si une dépendance n'est pas ✅, signale-le à Rayan et arrête-toi (propose l'ordre correct).
- Vérifie que la tâche n'est pas déjà ✅. Si elle est 🟧, demande à Rayan si on reprend là où on s'était arrêté.
- Relève les « Manuel (Rayan) » **préalables** au développement (compte à créer, clé API, appareil requis) : si le développement en dépend, demande confirmation qu'ils sont faits avant de continuer.

## 3. Lever les ambiguïtés et valider le plan — AVANT de coder

- Liste les points ambigus ou les décisions ouvertes de la tâche (choix de package, comportement UX non spécifié, seuil non défini...). Pose ces questions à Rayan maintenant.
- Présente ensuite un plan d'implémentation court : fichiers créés/modifiés, approche, tests prévus.
- **Attends la validation explicite de Rayan avant d'écrire la moindre ligne de code.** S'il n'y a aucune ambiguïté, dis-le et présente quand même le plan pour validation.

## 4. Développer

- Passe le statut de la tâche à 🟧 dans le fichier de tâches.
- Implémente en respectant strictement `cowork/conventions.md` et les règles absolues de `CLAUDE.md` (ChangeNotifier natif, domain pur Dart, Result<T>, interfaces pour tout outil externe, pas de secret commité).
- Reste dans le périmètre de la tâche. Toute déviation du cadrage découverte en cours de route : arrête-toi et demande à Rayan.

## 5. Tester

- Écris les tests listés dans la section « Tests » de la tâche (en TDD quand c'est pertinent, notamment pour tout `domain/`).
- Exécute `flutter analyze` (0 warning exigé) puis `flutter test` (100 % vert exigé). Corrige jusqu'à y arriver. Ne jamais supprimer ni affaiblir un test pour le faire passer.
- Passe en revue les critères d'acceptation un par un : indique pour chacun s'il est vérifié automatiquement, vérifié manuellement, ou s'il nécessite une action de Rayan (appareil réel...).

## 6. Clôturer

Dans le fichier de tâches, mets à jour la tâche : statut ✅ **uniquement si** tous les critères vérifiables sans action de Rayan sont satisfaits (sinon reste 🟧 avec la raison), et ajoute une courte section « Réalisé » (date, décisions prises, écarts éventuels).

Termine ta réponse par exactement quatre blocs :

1. **Résumé** — ce qui a été fait, fichiers créés/modifiés, décisions prises pendant la tâche.
2. **Critères d'acceptation** — état de chacun (✅ / ⚠️ à vérifier manuellement / ❌ avec raison).
3. **Actions manuelles pour Rayan** — la liste « Manuel (Rayan) » de la tâche + toute vérification sur appareil réel nécessaire. S'il n'y en a pas, le dire.
4. **Commit proposé** — un message Conventional Commits (anglais, scope = feature concernée), ex. `feat(session): add versioned websocket protocol DTOs`. **Ne commite pas** : Rayan valide d'abord.
