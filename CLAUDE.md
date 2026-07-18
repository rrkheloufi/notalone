# NotAlone — Contexte projet

App Flutter (iOS + Android) pour personnes sourdes/malentendantes : chaque convive capte **sa propre voix** avec son téléphone, les transcripts fusionnent en temps réel sur le téléphone du lecteur en un fil type messagerie. 100 % réseau local, sans compte, sans internet requis. Cas fondateur : le père de Rayan, quasiment sourd, aux repas de famille.

## Règles absolues

1. **Pas de Riverpod, pas de provider, pas de bloc, pas de get_it.** MVVM avec `ChangeNotifier` natif, `ListenableBuilder`, pattern Command (guide officiel Flutter). DI manuelle par constructeur, composée dans `app_dependencies.dart`.
2. **L'audio brut ne quitte jamais le téléphone qui l'a capté** et n'est jamais écrit sur disque. Seul le texte transite.
3. **`domain/` = pur Dart, zéro import Flutter.** Tout outil externe (STT, VAD, transport, LLM) est derrière une interface de `domain/` — on doit pouvoir changer de fournisseur en ne touchant que `data/`.
4. Erreurs via `Result<T>`/`Failure` ; aucune exception ne traverse la couche data.
5. Transcript éphémère par défaut ; aucune persistance non prévue par une tâche.
6. Aucun secret dans le dépôt (clés API via `--dart-define`).
7. Jamais de `Platform.isIOS/isAndroid` hors des factories prévues.
8. Avant tout commit : `flutter analyze` 0 warning + `flutter test` 100 % vert.
9. UX : rejoindre une session = scanner un QR, c'est tout. Toute friction ajoutée se discute avec Rayan.
10. Ne pas dévier du cadrage (`cowork/`) sans l'accord explicite de Rayan.

## Documents de référence (source de vérité)

| Fichier | Contenu |
|---|---|
| `cowork/01-cadrage-produit.md` | Vision, UX cible, décisions actées, périmètres MVP/v1/v2, critères de succès |
| `cowork/02-architecture.md` | Pipeline audio, protocole WebSocket, dédup cross-talk, structure du code, matrice STT, contraintes OS |
| `cowork/03-risques-rgpd-roadmap.md` | Risques, RGPD (biométrie v1), roadmap, plan de test |
| `cowork/conventions.md` | Clean code, style, tests, git, workflow |
| `cowork/tasks/tasks-mvp.md` / `tasks-v1.md` | Tâches avec statuts, dépendances, critères d'acceptation — **avancement = ces fichiers** |

## Architecture en bref

- Invité : mic continu → VAD Silero (ONNX) → filtre énergie → `SttEngine` (natif on-device par défaut, Gladia cloud en option) → envoi `speech_segment` en WebSocket LAN.
- Hôte : serveur WebSocket `dart:io` sur son téléphone, sync horloge par invité, buffer de réordonnancement ~1,5 s, déduplication cross-talk (chevauchement temporel × similarité texte, le plus énergique gagne), affichage accessible (bulles prénom+couleur, tailles XL, auto-scroll intelligent).
- Découverte : QR code (`{version, sessionName, host, port, token}`) + mDNS `_notalone._tcp` en secours.
- Structure : `app/lib/features/{onboarding,session,capture,transcript,settings}/` chacune en `domain/data/presentation`. Détail : doc 02 §7.

## Pourquoi le pipeline est maison (ne pas « simplifier »)

Les API STT natives sont limitées (iOS : 1 min/session ; Android : timeout 5 s + bips OEM). On capture nous-mêmes et on soumet des **segments courts** au moteur. Ne jamais brancher `SpeechRecognizer`/`SFSpeechRecognizer` en écoute continue directe.

## Commandes

Flutter est épinglé via **fvm** (`.fvmrc` à la racine, source de vérité aussi pour la CI) : toujours préfixer les commandes par `fvm`.

```bash
cd app
fvm flutter analyze --fatal-infos   # doit rendre 0 issue
fvm flutter test                    # doit passer intégralement
fvm flutter run --dart-define=GLADIA_API_KEY=xxx   # clé optionnelle (moteur cloud)
```

## Workflow

Développement uniquement via `/dev-task <ID>` (ex. `/dev-task MVP-04`) : la commande charge le contexte, vérifie les dépendances, lève les ambiguïtés avec Rayan **avant** de coder, développe, teste, met à jour le statut de la tâche, résume et propose un commit. Ne jamais commiter sans l'accord de Rayan. Les tâches « Manuel (Rayan) » ne sont jamais exécutées par l'IA : les rappeler en fin de tâche.
