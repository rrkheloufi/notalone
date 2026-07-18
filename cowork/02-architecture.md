# 02 — Architecture technique

> Référence technique du projet. À lire avant toute tâche touchant au pipeline, au protocole ou à la structure du code.

## 1. Vue d'ensemble

```
  TÉLÉPHONE INVITÉ (×N)                      TÉLÉPHONE HÔTE (lecteur)
┌─────────────────────────────┐            ┌──────────────────────────────┐
│ Micro (capture continue)    │            │ Serveur WebSocket (dart:io)  │
│   ↓                         │            │   ↓                          │
│ VAD (Silero ONNX)           │  WebSocket │ Sync horloges (offset/invité)│
│   ↓ segments de parole      │   (LAN)    │   ↓                          │
│ Filtre énergie (RMS)        │ ─────────► │ Réordonnancement (~1,5 s)    │
│   ↓                         │            │   ↓                          │
│ SttEngine (natif ou cloud)  │            │ Déduplication cross-talk     │
│   ↓                         │            │   ↓                          │
│ Envoi {texte, t, énergie}   │            │ Transcript UI (fil bulles)   │
└─────────────────────────────┘            └──────────────────────────────┘
```

L'audio brut ne quitte **jamais** le téléphone qui l'a capté. Seul le texte transite (+ métadonnées).
L'hôte est aussi un invité de sa propre session (il capte sa propre voix avec le même pipeline).

## 2. Pourquoi un pipeline audio maison

Les API STT natives sont conçues pour de la dictée courte : iOS `SFSpeechRecognizer` impose ~1 min/session et ~1000 req/h ; Android `SpeechRecognizer` coupe après ~5 s de silence, avec bips de relance selon les OEM. On ne leur laisse donc jamais le micro : on capture nous-mêmes en continu, notre VAD découpe des **segments courts** (une prise de parole = quelques secondes), et chaque segment est soumis au moteur STT. Les limites OS deviennent sans objet et les moteurs sont interchangeables.

## 3. Matrice des moteurs STT

| Moteur | Implémentation | Quand |
|---|---|---|
| iOS ≥ 26 | `SpeechAnalyzer` (on-device) via platform channel | Défaut iOS récent |
| iOS < 26 | `SFSpeechRecognizer` par segment | Défaut iOS ancien |
| Android 13+ | `createOnDeviceSpeechRecognizer` par segment | Défaut Android (fallback engine standard si absent) |
| Cloud | Gladia (streaming FR, code-switching, tier gratuit) | Option réglage, si internet |

Tous derrière l'interface unique `SttEngine` (voir §6). Le choix du moteur est une **stratégie** sélectionnée au runtime : jamais de `if (Platform.isIOS)` en dehors de la factory.

## 4. Protocole de session (WebSocket, JSON, versionné)

- Transport : WebSocket sur le LAN. Hôte = serveur `dart:io HttpServer` sur port éphémère.
- Découverte : QR code (payload : `{version, sessionName, host, port, token}`) + annonce mDNS/Bonjour (`_notalone._tcp`) en secours.
- Toute enveloppe : `{v: 1, type: string, payload: {...}}`. Champs inconnus ignorés (tolérance ascendante).

Messages principaux :

| Type | Sens | Payload (essentiel) |
|---|---|---|
| `join_request` | invité → hôte | `{name, token, appVersion}` |
| `join_ack` | hôte → invité | `{participantId, colorIndex, clockOffsetProbe}` |
| `clock_sync` | aller-retour ×5 à la connexion | échange type NTP → l'hôte calcule l'offset par invité |
| `speech_segment` | invité → hôte | `{segmentId, tStartMs, tEndMs, text, isFinal, energyDb, engine}` |
| `mic_status` | invité → hôte | `{state: active/interrupted/muted, batteryPct}` |
| `transcript_update` | hôte → miroirs (v1) | entrées fusionnées |
| `session_end` | hôte → tous | — ; chaque client efface tout |
| `ping`/`pong` | bidirectionnel | keepalive 5 s ; 3 échecs = déconnecté |

Reconnexion : l'invité retente avec backoff (1/2/4 s) en conservant son `participantId`.

## 5. Fusion côté hôte (cœur du produit — pur Dart, testé à fond)

1. **Normalisation temporelle** : `tStart` corrigé par l'offset d'horloge de l'invité émetteur.
2. **Réordonnancement** : buffer de ~1,5 s avant affichage (les latences STT diffèrent d'un téléphone à l'autre) ; passé ce délai, l'entrée est figée — jamais de saut de texte sous les yeux du lecteur.
3. **Déduplication cross-talk** : deux segments qui se **chevauchent temporellement** (IoU > seuil) avec un **texte similaire** (Levenshtein normalisée sur texte nettoyé > seuil) = même phrase captée par deux micros → on garde celui à l'énergie la plus forte et on l'attribue à son propriétaire. Seuils dans `DedupConfig` (calibrés en MVP-15).
4. Les résultats partiels (`isFinal: false`) sont affichés atténués puis remplacés ; ils ne participent pas à la dédup.

## 6. Clean Architecture + MVVM ChangeNotifier

Conforme au [guide d'architecture officiel Flutter](https://docs.flutter.dev/app-architecture) : MVVM, ViewModels = `ChangeNotifier`, vues via `ListenableBuilder`, actions via le **pattern Command**. **Pas de Riverpod, pas de package provider** : DI par constructeur, composition à la racine (`app_dependencies.dart`).

Règles de dépendance (strictes) :

- `domain/` : entités + interfaces de repositories + use cases. **Zéro import Flutter.** Tout le cœur (dédup, réordonnancement, protocole) est ici, testable en pur Dart.
- `data/` : implémentations des repositories + datasources (micro, VAD, STT, réseau). Dépend de `domain/`, jamais l'inverse.
- `presentation/` : Views (widgets purs, zéro logique) + ViewModels (`ChangeNotifier`, zéro import de widgets). Un ViewModel reçoit ses use cases par constructeur.
- Toute frontière vers un outil externe (moteur STT, VAD, transport, LLM en v1) = une **interface dans `domain/`** + une implémentation dans `data/`. Changer d'outil ne touche jamais ni `domain/` ni `presentation/`.
- Erreurs : `Result<T>` (sealed class `Ok`/`Err` avec `Failure` typée). Pas d'exception au-delà de la couche data.
- DTOs réseau : classes immutables manuelles + `toJson`/`fromJson` testés (pas de génération de code au MVP).

## 7. Arborescence du dépôt

```
notalone/
├── CLAUDE.md                      # Contexte IA (envoyé à chaque requête)
├── .claude/commands/dev-task.md   # Commande /dev-task
├── cowork/                        # Cadrage (source de vérité)
│   ├── 01-cadrage-produit.md
│   ├── 02-architecture.md         # (ce fichier)
│   ├── 03-risques-rgpd-roadmap.md
│   ├── conventions.md
│   └── tasks/
│       ├── tasks-mvp.md
│       └── tasks-v1.md
└── app/                           # Projet Flutter (créé en MVP-01)
    ├── lib/
    │   ├── main.dart
    │   ├── app.dart                       # MaterialApp, routes, thème
    │   ├── app_dependencies.dart          # Racine de composition (DI manuelle)
    │   ├── core/
    │   │   ├── result/                    # Result<T>, Failure
    │   │   ├── theme/                     # Typo XL, contrastes, couleurs locuteurs
    │   │   └── utils/                     # SyncedClock, extensions
    │   ├── features/
    │   │   ├── onboarding/                # Prénom, permissions (1ʳᵉ fois seulement)
    │   │   ├── session/
    │   │   │   ├── domain/                # Session, Participant, SessionRepository,
    │   │   │   │                          # protocole (DTOs, versions)
    │   │   │   ├── data/                  # HostServer (dart:io), GuestClient,
    │   │   │   │                          # mDNS, QR payload
    │   │   │   └── presentation/          # home_view, host_lobby_view, join_view
    │   │   │                              # + viewmodels
    │   │   ├── capture/
    │   │   │   ├── domain/                # SpeechSegment, SttEngine (interface),
    │   │   │   │                          # VadService (interface), CaptureSpeechUseCase
    │   │   │   ├── data/                  # mic_datasource, silero_vad,
    │   │   │   │                          # stt/{ios_native, android_native, gladia}
    │   │   │   └── presentation/          # capture_view (état micro) + viewmodel
    │   │   ├── transcript/
    │   │   │   ├── domain/                # TranscriptEntry, MergeTranscriptsUseCase
    │   │   │   │                          # (réordonnancement + dédup), DedupConfig
    │   │   │   ├── data/
    │   │   │   └── presentation/          # transcript_view (bulles, auto-scroll,
    │   │   │                              # filtre locuteur) + viewmodel
    │   │   └── settings/                  # Moteur STT, tailles, prénom
    │   └── shared/widgets/                # Widgets communs accessibles
    ├── test/                              # Miroir de lib/
    ├── ios/                               # UIBackgroundModes audio, Info.plist
    └── android/                           # Foreground service micro, Manifest
```

## 8. Contraintes plateformes (à traiter dans les tâches dédiées)

- **iOS** : `UIBackgroundModes: audio` pour capter écran verrouillé (justification App Store à préparer, voir doc 03) ; permissions micro + reconnaissance vocale ; gestion `AVAudioSession` interruptions (appel entrant → `mic_status: interrupted`).
- **Android** : foreground service `microphone` avec notification persistante ; exemption d'optimisation batterie à demander proprement ; bips OEM évités car on n'utilise jamais `SpeechRecognizer` en écoute continue ; modèle FR on-device à vérifier/télécharger au premier lancement.
- **Réseau local** : iOS 14+ demande la permission « Local Network » — l'expliquer dans l'UI au moment du besoin.

## 9. Packages pressentis (à valider à l'usage, versions figées en MVP-01)

`record` (capture PCM), `onnxruntime` (Silero VAD), `qr_flutter` + `mobile_scanner` (QR), `multicast_dns` ou `nsd` (mDNS), `shared_preferences` (prénom, réglages), `battery_plus`, `wakelock_plus` (écran hôte), `web_socket_channel` (client), `flutter_lints` renforcé par `very_good_analysis`. Platform channels maison pour STT natif (aucun plugin fiable pour notre usage segmenté).
