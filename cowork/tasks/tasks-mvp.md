# Tâches MVP

> Source de vérité de l'avancement MVP. Exécuter avec `/dev-task MVP-XX`.
> Statuts : ⬜ à faire · 🟧 en cours · ✅ fait. Une tâche ne démarre que si toutes ses dépendances sont ✅.
> « Manuel (Rayan) » = actions que l'IA ne fait pas ; elle les rappelle en fin de tâche.

---

### MVP-01 — Initialisation du projet Flutter et socle qualité

- **Statut** : ✅ fait
- **Dépend de** : —
- **Objectif** : créer `app/` (projet Flutter), la structure de dossiers de `cowork/02-architecture.md` §7, le socle `core/` (`Result<T>`, `Failure`, thème accessibilité de base, strings FR centralisées), lints `very_good_analysis`, CI GitHub Actions (analyze + test).
- **Critères d'acceptation** : `flutter analyze` 0 warning ; `flutter test` passe (tests du socle `Result<T>`) ; CI verte sur un push ; arborescence conforme au doc 02 §7 ; aucun package de state management/DI dans `pubspec.yaml`.
- **Tests** : unitaires `Result<T>` (ok/err, map, fold).
- **Manuel (Rayan)** : avoir Flutter stable installé (`flutter doctor` sain) ; créer le dépôt GitHub et pousser ; vérifier que la CI se déclenche.
- **Réalisé** (18/07/2026) :
  - `git init` (branche `main`) dans `notalone/` — le home était un repo git accidentel, la CI exige la racine ici. Flutter **3.44.6** épinglé via **fvm** (`.fvmrc` commité, source de vérité de la CI ; toutes les commandes passent par `fvm flutter …`, `CLAUDE.md` mis à jour).
  - Projet `app/` créé (template vide, iOS + Android, org `fr.rsquare` → bundle `fr.rsquare.notalone`).
  - Socle `core/` : `Result<T>` sealed (`Ok`/`Err`, `map`/`fold`, égalité par valeur) + `Failure` de base ; thème M3 contraste maximal clair/sombre (`contrastLevel: 1`) + palette 8 couleurs locuteurs ; strings via **easy_localization** (décision Rayan), FR seul (`assets/translations/fr.json`), clés centralisées dans `L10nKeys` sans codegen.
  - Écarts assumés : `core/l10n/` remplace le `core/strings/` pressenti ; lint `public_member_api_docs` désactivée (conventions anti-paraphrase) ; CI stricte `flutter analyze --fatal-infos` ; `meta` ajouté pour `@immutable` sans importer Flutter dans `core/result/`.
  - Vérifié : analyze 0 issue, 9/9 tests verts. CI verte sur push : en attente du repo GitHub (action Rayan).

### MVP-02 — Spike de dérisquage : VAD temps réel on-device

- **Statut** : 🟧 en cours
- **Dépend de** : MVP-01
- **Objectif** : prouver que Silero VAD (ONNX) tourne en continu sur téléphone avec `record` (PCM 16 kHz) : détection début/fin de parole + mesure d'énergie RMS par segment. Écran de debug jetable (niveaux, segments détectés).
- **Critères d'acceptation** : sur appareil réel, la parole est segmentée avec < 300 ms de retard de détection ; une voix à 1,5 m est distinguable d'une voix à 30 cm par l'énergie ; CPU/batterie raisonnables sur 15 min (observation).
- **Tests** : unitaires de la logique de segmentation (états silence/parole, hystérésis) sur buffers synthétiques ; le modèle ONNX lui-même est testé manuellement.
- **Manuel (Rayan)** : tester sur 1 iPhone + 1 Android réels ; noter les mesures (retard, batterie) dans la tâche. **Go/no-go** : si le VAD ne tient pas, on pivote (VAD énergie simple) avant d'aller plus loin.
- **Réalisé** (18/07/2026 — code terminé, en attente des tests appareil réel de Rayan) :
  - Runtime ONNX : `flutter_onnxruntime` 1.8.2 retenu (validé avec Rayan) — le package `onnxruntime` pressenti au doc 02 §9 est à l'abandon (dernière publication 03/2024). Modèle **Silero VAD v5** commité en asset (`app/assets/models/silero_vad.onnx`, 2,3 Mo, MIT). Protocole d'appel (contexte glissant 64 samples, état LSTM [2,1,128], `sr` int64) validé contre onnxruntime desktop avant écriture du code Dart.
  - `capture/domain/` pur Dart et pérenne (repris tel quel en MVP-08) : `VadConfig` (seuils par défaut : hystérésis 0,5/0,35, minSpeech 200 ms, minSilence 600 ms — à calibrer en MVP-15), `SpeechSegmenter` (machine à états + énergie RMS dBFS, micro-pauses absorbées, énergie du silence de clôture exclue), interfaces `VadService`/`MicAudioSource`, `AudioLevel`. Jetables : écran `vad_debug_view` + ViewModel.
  - Ajout au socle : `core/command/` (pattern Command du guide Flutter, exigé par les conventions pour les ViewModels).
  - Capture via `record` 7.1.1 (PCM16 16 kHz mono, AGC/débruitage désactivés pour préserver l'énergie ; rien sur disque). Plateforme : `RECORD_AUDIO` (Android), `NSMicrophoneUsageDescription` (iOS), Podfile iOS 16 + linkage statique et deployment target 16.0 (exigences ONNX Runtime), règles ProGuard ORT.
  - Vérifié : analyze 0 issue, 40/40 tests verts (segmenteur exhaustif, RMS, Command, ViewModel avec fakes). Critères « retard < 300 ms », « 30 cm vs 1,5 m », « CPU/batterie 15 min » : à mesurer par Rayan sur appareils réels (go/no-go).

### MVP-03 — Spike de dérisquage : session LAN 2 téléphones

- **Statut** : ⬜ à faire
- **Dépend de** : MVP-01
- **Objectif** : prouver la chaîne hôte/invité : serveur WebSocket `dart:io` sur le téléphone hôte, QR code affiché (payload IP:port:token), scan par l'invité, échange de messages texte, permission « Local Network » iOS gérée.
- **Critères d'acceptation** : 2 téléphones réels sur le même WiFi échangent des messages < 200 ms ; le QR suffit (pas de saisie manuelle) ; comportement documenté quand le WiFi isole les clients (R7 du doc 03).
- **Tests** : unitaires encode/décode du payload QR ; test d'intégration serveur/client en pur Dart (2 isolates).
- **Manuel (Rayan)** : test sur le WiFi de la maison familiale si possible ; tester aussi en partage de connexion. **Go/no-go** technique à l'issue des 2 spikes.

### MVP-04 — Protocole de session (DTOs versionnés)

- **Statut** : ⬜ à faire
- **Dépend de** : MVP-03
- **Objectif** : implémenter dans `session/domain/` le protocole complet du doc 02 §4 : enveloppe `{v, type, payload}`, DTOs immutables (`JoinRequest`, `JoinAck`, `ClockSync`, `SpeechSegmentDto`, `MicStatus`, `SessionEnd`, `Ping/Pong`), sérialisation JSON, tolérance aux champs inconnus.
- **Critères d'acceptation** : round-trip JSON exact pour chaque message ; un message de version supérieure avec champs inconnus est accepté ; un message malformé produit une `Failure` typée (jamais d'exception).
- **Tests** : unitaires exhaustifs par DTO (round-trip, malformés, champs inconnus) — c'est le contrat du produit, viser 100 %.
- **Manuel (Rayan)** : —

### MVP-05 — Serveur hôte : cycle de vie de session

- **Statut** : ⬜ à faire
- **Dépend de** : MVP-04
- **Objectif** : `HostServer` dans `session/data/` : démarrage sur port éphémère, génération du token, accept des `join_request` (max 8, rejet propre au-delà), registre des participants (id, prénom, couleur), keepalive ping/pong 5 s, détection de déconnexion (3 échecs), reconnexion avec conservation du `participantId`, diffusion `session_end`.
- **Critères d'acceptation** : 8 invités simulés se connectent, échangent, se déconnectent/reconnectent sans fuite d'état ; un token invalide est rejeté ; `session_end` efface l'état serveur.
- **Tests** : intégration pur Dart (serveur + N clients simulés) couvrant join/rejet/reconnexion/fin ; unitaires du registre de participants.
- **Manuel (Rayan)** : —

### MVP-06 — Rejoindre : QR, mDNS, client invité

- **Statut** : ⬜ à faire
- **Dépend de** : MVP-05
- **Objectif** : `GuestClient` (connexion, backoff 1/2/4 s, file d'envoi) ; génération QR côté hôte (`qr_flutter`) ; scan côté invité (`mobile_scanner`) ; annonce et découverte mDNS `_notalone._tcp` en secours du QR ; écrans host_lobby (QR + liste des invités) et join (scan → confirmation prénom → connecté) avec leurs ViewModels.
- **Critères d'acceptation** : parcours « scanner → connecté » < 10 s sur appareils réels ; coupure WiFi de 5 s → reconnexion transparente ; mDNS trouve la session si le scan échoue ; ViewModels testés sans widget.
- **Tests** : unitaires ViewModels (états scan/connexion/erreur via Commands) ; intégration client contre `HostServer` ; widget tests des 2 écrans.
- **Manuel (Rayan)** : valider le parcours réel avec 2 téléphones ; chronométrer.

### MVP-07 — Onboarding minimal et écran d'accueil

- **Statut** : ⬜ à faire
- **Dépend de** : MVP-01
- **Objectif** : premier lancement = saisie du prénom (persisté `shared_preferences`), puis home à 2 boutons : « Nouvelle conversation » / « Rejoindre ». Permissions demandées contextuellement (micro au premier join/host, caméra au premier scan) avec une phrase d'explication. Prénom modifiable dans `settings/`.
- **Critères d'acceptation** : lancements suivants → home direct ; refus de permission → écran d'explication avec lien réglages système, pas de crash ; conforme UX doc 01 §3.
- **Tests** : unitaires ViewModel onboarding ; widget tests home + refus de permission (permission service mocké derrière interface `domain/`).
- **Manuel (Rayan)** : —

### MVP-08 — Pipeline de capture industrialisé (invité)

- **Statut** : ⬜ à faire
- **Dépend de** : MVP-02, MVP-04
- **Objectif** : transformer le spike MVP-02 en `capture/` propre : `CaptureSpeechUseCase` orchestrant mic → VAD → filtre énergie (seuil dans `VadConfig`) → émission de `SpeechSegment` horodatés. Capture maintenue écran verrouillé : foreground service `microphone` Android (+ demande d'exemption batterie), `UIBackgroundModes: audio` + gestion des interruptions `AVAudioSession` iOS → événements `mic_status`.
- **Critères d'acceptation** : 30 min de capture écran verrouillé sans interruption sur les 2 OS ; un appel entrant émet `mic_status: interrupted` puis reprise auto ; segments < 15 s (découpe forcée au-delà) ; aucune donnée audio écrite sur disque.
- **Tests** : unitaires use case (fixtures de buffers : silence/parole/voix faible) ; test manuel scripté des interruptions (checklist dans la tâche).
- **Manuel (Rayan)** : exécuter la checklist interruptions sur les 2 OS (appel entrant, notification, verrouillage, 30 min).

### MVP-09 — Horloge synchronisée et réordonnancement

- **Statut** : ⬜ à faire
- **Dépend de** : MVP-04
- **Objectif** : `SyncedClock` (échange `clock_sync` ×5 à la connexion, offset médian par invité) et buffer de réordonnancement côté hôte (fenêtre 1,5 s configurable) dans `transcript/domain/`. Pur Dart.
- **Critères d'acceptation** : offsets simulés de ±2 s corrigés à ±50 ms près ; les entrées sortent du buffer dans l'ordre temporel corrigé ; une entrée arrivée après la fenêtre est insérée sans réordonner ce qui est déjà figé (marquée tardive).
- **Tests** : unitaires exhaustifs (offsets extrêmes, jitter, arrivées tardives, horloges qui dérivent).
- **Manuel (Rayan)** : —

### MVP-10 — Moteurs STT natifs (iOS + Android)

- **Statut** : ⬜ à faire
- **Dépend de** : MVP-08
- **Objectif** : interface `SttEngine` dans `capture/domain/` (`transcribe(SpeechSegment) → Result<Transcription>` + capacités : partiels, langue). Implémentations par platform channels : iOS `SpeechAnalyzer` (≥ iOS 26) / `SFSpeechRecognizer` (fallback), Android `createOnDeviceSpeechRecognizer` (API 33+, fallback engine standard). Factory de sélection (seul endroit avec du code par plateforme). Téléchargement/vérification du modèle FR on-device au premier lancement.
- **Critères d'acceptation** : phrase FR de 5 s transcrite < 1,5 s après fin de segment sur appareils réels ; segments enchaînés sans épuiser les quotas iOS (sessions courtes par segment) ; absence de modèle FR → `Failure` explicite + message UI ; aucun `Platform.isIOS` hors factory.
- **Tests** : unitaires factory + mapping erreurs natives → `Failure` ; contrat `SttEngine` avec fake ; qualité réelle testée manuellement (10 phrases scriptées par OS, taux d'erreur noté dans la tâche).
- **Manuel (Rayan)** : dérouler les 10 phrases sur les 2 OS ; vérifier le modèle FR hors-ligne (mode avion).

### MVP-11 — Fusion et déduplication cross-talk (hôte)

- **Statut** : ⬜ à faire
- **Dépend de** : MVP-09
- **Objectif** : `MergeTranscriptsUseCase` dans `transcript/domain/` : consomme les `speech_segment` de tous les invités, applique horloge corrigée + réordonnancement (MVP-09) + déduplication (chevauchement IoU × similarité Levenshtein normalisée, seuils dans `DedupConfig`) → flux de `TranscriptEntry` attribués. Les partiels ne participent pas à la dédup. Cœur du produit, pur Dart.
- **Critères d'acceptation** : sur fixtures scriptées (mêmes phrases captées par 2 « micros » avec décalages/variantes de texte), taux de doublons en sortie < 5 % sans perte de vraies phrases ; le segment le plus énergique gagne l'attribution ; performances : 8 flux × 2 h simulés sans dérive mémoire.
- **Tests** : la suite la plus fournie du projet — scénarios cross-talk, phrases simultanées distinctes (ne PAS dédupliquer), textes proches mais temporellement disjoints (ne PAS dédupliquer), stress 8 flux. ≥ 90 % de couverture.
- **Manuel (Rayan)** : relire les scénarios de fixtures et confirmer qu'ils reflètent un vrai repas.

### MVP-12 — UI du transcript (écran lecteur)

- **Statut** : ⬜ à faire
- **Dépend de** : MVP-11
- **Objectif** : `transcript_view` + ViewModel : bulles prénom + couleur stable, partiels atténués puis figés, tailles de police réglables (jusqu'à très grande), contraste élevé, mode sombre, **auto-scroll intelligent** (suspendu si le lecteur remonte, badge « N nouveaux messages », jamais de scroll forcé), filtre par locuteur (appui sur un prénom), `wakelock` écran hôte.
- **Critères d'acceptation** : lisible à 60 cm en taille max ; le réordonnancement ne fait jamais sauter le texte déjà lu ; filtre locuteur activable/désactivable en 1 geste ; conforme doc 01 §3.
- **Tests** : unitaires ViewModel (flux d'entrées, filtre, état de scroll) ; widget tests ; golden tests aux 3 tailles de police.
- **Manuel (Rayan)** : faire valider la lisibilité par ton père (taille, contraste, vitesse) — retour direct du persona lecteur.

### MVP-13 — Supervision, fin de session, réglages

- **Statut** : ⬜ à faire
- **Dépend de** : MVP-06, MVP-08, MVP-12
- **Objectif** : panneau hôte des invités (actif / interrompu / batterie faible / déconnecté, depuis `mic_status` + keepalive) avec alertes non intrusives (« le micro de Paul est coupé ») ; fin de session propre (`session_end` → effacement partout, écran de confirmation) ; réglages : moteur STT (natif/cloud), taille de police, prénom.
- **Critères d'acceptation** : coupure du micro d'un invité visible chez l'hôte < 10 s ; après fin de session, aucune trace du transcript sur aucun appareil (vérifiable) ; réglages persistés.
- **Tests** : unitaires ViewModels supervision + intégration `mic_status` bout en bout (client simulé) ; test manuel d'effacement.
- **Manuel (Rayan)** : vérifier l'effacement effectif sur les 2 OS après une vraie session.

### MVP-14 — Moteur STT cloud optionnel (Gladia)

- **Statut** : ⬜ à faire
- **Dépend de** : MVP-10
- **Objectif** : implémentation `GladiaSttEngine` de l'interface `SttEngine` (envoi des segments, FR), activable par invité dans les réglages, grisée sans internet, clé API via `--dart-define` (jamais commitée). Bascule dynamique natif↔cloud sans redémarrer la session.
- **Critères d'acceptation** : bascule en cours de session OK ; panne cloud → repli automatique sur le natif + info discrète ; aucun secret dans le dépôt ; le reste du code ignore quel moteur tourne.
- **Tests** : contrat `SttEngine` sur fake HTTP ; unitaires du repli ; test manuel qualité (mêmes 10 phrases que MVP-10, comparaison notée).
- **Manuel (Rayan)** : créer le compte Gladia, générer la clé (tier gratuit 480 min/mois), la fournir en variable d'environnement.

### MVP-15 — Calibration terrain et test famille

- **Statut** : ⬜ à faire
- **Dépend de** : MVP-13, MVP-14
- **Objectif** : calibrer `VadConfig` et `DedupConfig` sur données réelles ; dérouler le protocole cross-talk du doc 03 §4 (2 puis 4 personnes, phrases scriptées simultanées, mesure doublons/faux messages/latence) ; instrumenter des compteurs de session locaux (segments émis/dédupliqués/tardifs, batterie) pour objectiver ; puis test famille réel.
- **Critères d'acceptation** : critère de succès MVP du doc 01 §9 atteint (≥ 80 % qui/quoi, doublons < 5 %, latence < 2 s, batterie ≥ 2 h) ; seuils finaux commités avec justification ; grille d'observation du repas remplie.
- **Tests** : les mesures terrain elles-mêmes ; tests de non-régression rejoués avec les seuils finaux.
- **Manuel (Rayan)** : organiser les 2 sessions de test (protocole scripté, puis repas famille avec ton père), remplir la grille, faire le débrief. **Jalon final MVP** — la décision « v1 avec ou sans vérification locuteur » se prend ici (cf. doc 03 R2/R3).
