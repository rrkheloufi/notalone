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

- **Statut** : ✅ fait
- **Dépend de** : MVP-01
- **Objectif** : prouver que Silero VAD (ONNX) tourne en continu sur téléphone avec `record` (PCM 16 kHz) : détection début/fin de parole + mesure d'énergie RMS par segment. Écran de debug jetable (niveaux, segments détectés).
- **Critères d'acceptation** : sur appareil réel, la parole est segmentée avec < 300 ms de retard de détection ; une voix à 1,5 m est distinguable d'une voix à 30 cm par l'énergie ; CPU/batterie raisonnables sur 15 min (observation).
- **Tests** : unitaires de la logique de segmentation (états silence/parole, hystérésis) sur buffers synthétiques ; le modèle ONNX lui-même est testé manuellement.
- **Manuel (Rayan)** : tester sur 1 iPhone + 1 Android réels ; noter les mesures (retard, batterie) dans la tâche. **Go/no-go** : si le VAD ne tient pas, on pivote (VAD énergie simple) avant d'aller plus loin.
- **Réalisé** (18/07/2026 — code terminé, en attente des tests appareil réel de Rayan) :
  - Runtime ONNX : `flutter_onnxruntime` 1.8.2 retenu (validé avec Rayan) — le package `onnxruntime` pressenti au doc 02 §9 est à l'abandon (dernière publication 03/2024). Modèle **Silero VAD v5** commité en asset (`app/assets/models/silero_vad.onnx`, 2,3 Mo, MIT). Protocole d'appel (contexte glissant 64 samples, état LSTM [2,1,128], `sr` int64) validé contre onnxruntime desktop avant écriture du code Dart.
  - `capture/domain/` pur Dart et pérenne (repris tel quel en MVP-08) : `VadConfig` (seuils par défaut : hystérésis 0,5/0,35, minSpeech 200 ms, minSilence 600 ms — à calibrer en MVP-15), `SpeechSegmenter` (machine à états + énergie RMS dBFS, micro-pauses absorbées, énergie du silence de clôture exclue), interfaces `VadService`/`MicAudioSource`, `AudioLevel`. Jetables : écran `vad_debug_view` + ViewModel.
  - Ajout au socle : `core/command/` (pattern Command du guide Flutter, exigé par les conventions pour les ViewModels).
  - Capture via `record` 7.1.1 (PCM16 16 kHz mono, AGC/débruitage désactivés pour préserver l'énergie ; rien sur disque). Plateforme : `RECORD_AUDIO` (Android), `NSMicrophoneUsageDescription` (iOS), deployment target iOS 16.0 (exigence ONNX Runtime), règles ProGuard ORT. Correctif 19/07 : le Podfile ajouté initialement provoquait une double intégration CocoaPods/Swift Package Manager (« sandbox is not in sync with the Podfile.lock » sur iPhone) — retiré, les plugins iOS passent par **SPM** (voie supportée par flutter_onnxruntime, deployment target 16.0 suffit).
  - Vérifié : analyze 0 issue, 40/40 tests verts (segmenteur exhaustif, RMS, Command, ViewModel avec fakes). Critères « retard < 300 ms », « 30 cm vs 1,5 m », « CPU/batterie 15 min » : à mesurer par Rayan sur appareils réels (go/no-go).
  - Correctif 19/07 : `ORT_INVALID_ARGUMENT` sur appareil (iOS + Android) au premier `run` — le tenseur `sr` partait en int32 car le plugin mappe une `List<int>` Dart vers int32 ; passage à `Int64List` explicite (risque identifié dès la revue de l'API, non vérifiable hors appareil).
  - **Validé par Rayan (19/07/2026)** sur appareils réels, après le correctif int64 : les prises de parole sont bien segmentées, de près comme de loin ; énergie mesurée de **−39 dBFS (loin) à −14 dBFS (près)**, croissante avec la proximité du téléphone → le critère « 30 cm vs 1,5 m distinguables » est rempli. Retard de détection et CPU/batterie 15 min non chiffrés formellement, jugés bons à l'usage. **Go/no-go Phase 0 : GO** (les 2 spikes MVP-02 + MVP-03 sont validés).

### MVP-03 — Spike de dérisquage : session LAN 2 téléphones

- **Statut** : ✅ fait
- **Dépend de** : MVP-01
- **Objectif** : prouver la chaîne hôte/invité : serveur WebSocket `dart:io` sur le téléphone hôte, QR code affiché (payload IP:port:token), scan par l'invité, échange de messages texte, permission « Local Network » iOS gérée.
- **Critères d'acceptation** : 2 téléphones réels sur le même WiFi échangent des messages < 200 ms ; le QR suffit (pas de saisie manuelle) ; comportement documenté quand le WiFi isole les clients (R7 du doc 03).
- **Tests** : unitaires encode/décode du payload QR ; test d'intégration serveur/client en pur Dart (2 isolates).
- **Manuel (Rayan)** : test sur le WiFi de la maison familiale si possible ; tester aussi en partage de connexion. **Go/no-go** technique à l'issue des 2 spikes.
- **Réalisé** (19/07/2026 — code terminé, en attente des tests 2 téléphones de Rayan) :
  - Payload QR : JSON complet du doc 02 §4 `{version, sessionName, host, port, token}` (pas le raccourci « IP:port:token » du titre), dans `session/domain/qr_session_payload.dart` (pérenne) — décodage tolérant (champs inconnus ignorés, version supérieure acceptée), erreurs en `Failure` typées, testé exhaustivement.
  - Rendu QR : **`pretty_qr_code` 3.6.0** (validé avec Rayan) — `qr_flutter` pressenti au doc 02 §9 n'est plus publié depuis 05/2023. Scan : `mobile_scanner` 7.3.0. Client WS : `web_socket_channel` 3.0.3.
  - Interfaces `LanServer`/`LanClient` dans `session/domain/` (spike, remplacées par HostServer/GuestClient en MVP-05/06) ; impls `DartIoLanServer` (HttpServer port éphémère, token 128 bits `Random.secure`) et `WebSocketLanClient` (timeout 5 s) dans `session/data/` + `local_ip.dart`. Écart assumé : token vérifié en query string à l'upgrade WS, le vrai `join_request` arrive en MVP-04/05. Protocole texte minimal `{"type":"chat"|"ping"|"pong"}`, RTT mesuré par ping/pong applicatif (médiane sur 5, affichée chez l'invité pour le critère < 200 ms).
  - **R7 (WiFi isolant) documenté** : un timeout de connexion (TCP accepté mais session muette, ou pas de route) produit `ConnectionTimeoutFailure`, l'écran invité affiche alors : activer le partage de connexion du téléphone hôte, y reconnecter les 2 téléphones, rescanner. Cas reproduit en test d'intégration (« serveur muet »). Plan B hotspot = comportement nominal (le serveur écoute sur toutes les interfaces, `local_ip` préfère 192.168/10/172).
  - Écrans de debug jetables hôte (QR + journal + envoi) et invité (scan → RTT + messages) ; `Command1` ajouté au socle `core/command/`. Plateforme : `INTERNET` au manifest principal Android (le template ne l'a qu'en debug), `NSCameraUsageDescription` + `NSLocalNetworkUsageDescription` iOS.
  - Vérifié : analyze 0 issue, 64/64 tests verts dont intégration serveur réel + client dans un **second isolate** (connexion, ping, chat/écho, départ), rejet mauvais token, timeout R7, relais entre 2 invités sans écho à l'émetteur. Critères « < 200 ms sur 2 téléphones réels » et « le QR suffit » : à valider par Rayan (go/no-go des 2 spikes).
  - **Validé par Rayan (19/07/2026)** sur 2 téléphones réels : scan du QR → connexion → échange de messages OK. (Valeur du RTT médian non consignée — à ajouter ici si utile au go/no-go.) Le build iPhone a nécessité le passage à Swift Package Manager (correctif noté en MVP-02).

### MVP-04 — Protocole de session (DTOs versionnés)

- **Statut** : ✅ fait
- **Dépend de** : MVP-03
- **Objectif** : implémenter dans `session/domain/` le protocole complet du doc 02 §4 : enveloppe `{v, type, payload}`, DTOs immutables (`JoinRequest`, `JoinAck`, `ClockSync`, `SpeechSegmentDto`, `MicStatus`, `SessionEnd`, `Ping/Pong`), sérialisation JSON, tolérance aux champs inconnus.
- **Critères d'acceptation** : round-trip JSON exact pour chaque message ; un message de version supérieure avec champs inconnus est accepté ; un message malformé produit une `Failure` typée (jamais d'exception).
- **Tests** : unitaires exhaustifs par DTO (round-trip, malformés, champs inconnus) — c'est le contrat du produit, viser 100 %.
- **Manuel (Rayan)** : —
- **Réalisé** (19/07/2026) :
  - `session/domain/protocol/` : base sealed `SessionMessage` (switch exhaustifs garantis pour MVP-05/06, DTOs en `part` — un fichier par message) + `SessionMessageCodec` (enveloppe `{v, type, payload}`, table type→parseur, jamais d'exception). 8 messages : `JoinRequest`, `JoinAck`, `ClockSync`, `SpeechSegmentDto`, `MicStatus`, `SessionEnd`, `Ping`, `Pong` — immutables, égalité par valeur, `toJson`/`fromJson` manuels (doc 02 §6).
  - Décisions validées avec Rayan : `clock_sync` = un seul type wire, NTP 4 horodatages — l'hôte envoie `{seq, tHostSentMs}`, l'invité complète `{tGuestReceivedMs, tGuestSentMs}` (ensemble ou absents ensemble), offset `((t1−t0)+(t2−t3))/2` médiane ×5 calculé en MVP-09 ; `clockOffsetProbe` du `join_ack` = horodatage hôte à l'émission de l'ack (probe n°0) ; type de message inconnu → `UnknownMessageTypeFailure` dédiée (ignorable par l'appelant sans le confondre avec de la corruption), valeur d'enum inconnue → `MessageMalformedFailure` (strict : un émetteur v2 doit rester compatible v1 sur les enums).
  - Détails de contrat : seul `SpeechSegmentDto` est suffixé (collision à venir avec l'entité `SpeechSegment` de capture, MVP-08) ; `engine` en chaîne libre ; `participantId`/`segmentId` chaînes opaques ; `energyDb` décodé depuis tout `num` JSON ; `tEndMs ≥ tStartMs` exigé ; `ping`/`pong` portent un `seq` (appariement keepalive MVP-05 + mesure RTT).
  - Vérifié : analyze 0 issue, 124/124 tests verts, couverture lignes 100 % sur les 9 fichiers du protocole.
  - **Amendement (19/07/2026, MVP-05, validé par Rayan)** : `join_request` gagne un champ **`participantId` optionnel** (absent au premier join, repris de la `join_ack` à la reconnexion). C'est le mécanisme qui rend son identité et sa couleur à un invité qui revient ; l'ID étant un aléatoire 128 bits, il fait aussi office de jeton de reprise (un autre téléphone ne peut pas prendre une place en déclarant le même prénom). Rétro-compatible : un émetteur v1 sans le champ reste accepté. Couverture du protocole toujours 100 %.

### MVP-05 — Serveur hôte : cycle de vie de session

- **Statut** : ✅ fait
- **Dépend de** : MVP-04
- **Objectif** : `HostServer` dans `session/data/` : démarrage sur port éphémère, génération du token, accept des `join_request` (max 8, rejet propre au-delà), registre des participants (id, prénom, couleur), keepalive ping/pong 5 s, détection de déconnexion (3 échecs), reconnexion avec conservation du `participantId`, diffusion `session_end`.
- **Critères d'acceptation** : 8 invités simulés se connectent, échangent, se déconnectent/reconnectent sans fuite d'état ; un token invalide est rejeté ; `session_end` efface l'état serveur.
- **Tests** : intégration pur Dart (serveur + N clients simulés) couvrant join/rejet/reconnexion/fin ; unitaires du registre de participants.
- **Manuel (Rayan)** : —
- **Réalisé** (19/07/2026) :
  - Décisions validées avec Rayan avant de coder : (1) reconnexion par **`participantId` optionnel dans `join_request`** (amendement MVP-04 ci-dessus) plutôt que par matching de prénom — deux homonymes restent distincts et une place ne s'usurpe pas ; (2) refus par **codes de fermeture WebSocket** applicatifs plutôt que par un message `join_reject` — le protocole reste à 8 types ; (3) la limite de 8 **compte l'hôte**, qui capte sa propre voix (doc 02 §1) et consomme donc une place et une couleur → 7 invités connectés au maximum, aligné sur la palette de 8 couleurs ; (4) le spike MVP-03 (`LanServer`/`DartIoLanServer` + écrans de debug) est **conservé intact**, à supprimer en MVP-06 avec l'arrivée de `GuestClient`. MVP-05 est donc purement additif.
  - `session/domain/` : `SessionConfig` (8 participants, keepalive 5 s, 3 pongs manqués, joinTimeout 5 s — injectable pour rejouer le keepalive en millisecondes dans les tests), `Participant` (id opaque, prénom, couleur, hôte, connecté), `ParticipantRegistry` (**le cœur métier** : admission, plus petite couleur libre, reprise d'identité, déconnexion sans oubli, `clear()`), `HostServer` + événements sealed (`ParticipantJoined`/`Rejected`/`Disconnected`, `SessionMessageReceived`), `protocol/session_close_codes.dart` (4001 token invalide · 4002 session pleine · 4003 join absent/malformé · 4004 session terminée), failures `SessionFullFailure`/`InvalidTokenFailure`.
  - `session/data/DartIoHostServer` : port éphémère, token 128 bits, `join_ack` avec `clockOffsetProbe` (probe n°0 de MVP-09), keepalive périodique, réponse aux `ping` des invités, `endSession()` terminal (diffusion `session_end` → fermeture 4004 → registre vidé → serveur fermé).
  - **Écart assumé vs spike MVP-03** : le token ne circule plus en query string à l'upgrade mais se vérifie dans le `join_request`, au niveau du protocole — il ne traîne ni dans les URLs ni dans les journaux. Un socket qui n'envoie pas de `join_request` exploitable sous `joinTimeout` est fermé en 4003.
  - Règles de cycle de vie tranchées en cours de route (non spécifiées par les docs, notées ici) : une **reconnexion sur un participant encore marqué connecté est acceptée** et remplace le socket précédent — un WiFi qui tombe est constaté jusqu'à 15 s plus tard par le keepalive, refuser enfermerait l'invité dehors ; la **limite ne s'applique jamais à un revenant** ; un `participantId` **inconnu** vaut premier join plutôt que refus ; une couleur reste réservée à un absent, sauf palette saturée où celle du **plus ancien parti** est recyclée (il revient alors comme nouvel invité).
  - Deux bugs trouvés et corrigés par les tests : `await subscription.cancel()` avant `socket.close()` **bloquait la fermeture** d'un socket resté muet (le refus 4003 n'arrivait jamais) → on ferme le socket d'abord ; et côté test, `WebSocket.done` ne concerne que le sink sortant, la fin de connexion s'observe sur le flux entrant.
  - Vérifié : analyze 0 issue, **165/165 tests verts** (21 unitaires registre + participant, 16 d'intégration serveur réel avec invités WebSocket simulés, protocole complété). Couverture lignes : registre 98 %, `Participant` et `HostServer` 100 %, serveur 96 %. Aucun écran ni ViewModel (host_lobby = MVP-06), `app_dependencies.dart` inchangé.

### MVP-06 — Rejoindre : QR, mDNS, client invité

- **Statut** : ✅ fait
- **Dépend de** : MVP-05
- **Objectif** : `GuestClient` (connexion, backoff 1/2/4 s, file d'envoi) ; génération QR côté hôte (`qr_flutter`) ; scan côté invité (`mobile_scanner`) ; annonce et découverte mDNS `_notalone._tcp` en secours du QR ; écrans host_lobby (QR + liste des invités) et join (scan → confirmation prénom → connecté) avec leurs ViewModels.
- **Critères d'acceptation** : parcours « scanner → connecté » < 10 s sur appareils réels ; coupure WiFi de 5 s → reconnexion transparente ; mDNS trouve la session si le scan échoue ; ViewModels testés sans widget.
- **Tests** : unitaires ViewModels (états scan/connexion/erreur via Commands) ; intégration client contre `HostServer` ; widget tests des 2 écrans.
- **Manuel (Rayan)** : valider le parcours réel avec 2 téléphones ; chronométrer.
- **Réalisé** (20/07/2026 — code terminé, en attente du parcours 2 téléphones de Rayan) :
  - Décisions validées avec Rayan avant de coder : (1) mDNS via **`bonsoir` 7.1.4** — `multicast_dns` du doc 02 §9 ne sait que *découvrir*, jamais annoncer, il ne pouvait donc pas servir côté hôte ; `nsd` faisait l'affaire mais bonsoir est le plus activement maintenu ; (2) **le token voyage dans l'enregistrement TXT** de l'annonce : sans lui, un invité qui découvre la session resterait à la porte et le secours ne dépannerait personne. Le LAN est déjà la frontière de confiance (aucune donnée ne le quitte) et l'hôte voit arriver chaque convive dans son lobby ; (3) backoff **1/2/4 s puis plafonné à 4 s, abandon après 6 essais (~21 s)** et état terminal « connexion perdue » — couvre largement la coupure de 5 s du critère sans vider la batterie quand l'hôte a éteint pour de bon ; (4) le prénom vient d'un **champ modifiable pré-rempli** d'une valeur provisoire injectée depuis `app_dependencies` : MVP-07 remplacera l'injection par le prénom persisté sans toucher aux ViewModels.
  - `session/domain/` : `GuestClient` + `GuestSession` + événements sealed (`GuestReconnecting`/`Reconnected`/`ConnectionLost`/`SessionEnded`/`MessageReceived`), `GuestConfig` (timeouts, paliers de backoff, file d'envoi bornée à 200), `DiscoveredSession` (type `_notalone._tcp`, encodage/décodage du TXT record en pur Dart — le seul morceau mDNS testable en CI) + interfaces `SessionAdvertiser`/`SessionBrowser`, `protocol/session_wire.dart` (le chemin `/ws` remonte du `data/` : c'est un contrat de fil partagé par les deux bouts), failures `JoinRefusedFailure(closeCode)` / `DiscoveryRecordMalformedFailure` / `DiscoveryUnavailableFailure`.
  - `session/data/` : `WebSocketGuestClient` (join_ack, réponse `pong` au keepalive de l'hôte, reconnexion automatique rejouant le `join_request` avec le `participantId` conservé, file d'envoi vidée à la reprise) et `BonsoirSessionAdvertiser`/`BonsoirSessionBrowser`. `session/presentation/` : `host_lobby_view`/`viewmodel` et `join_view`/`viewmodel`. `app.dart` passe des 3 boutons de debug aux vrais « Nouvelle conversation » / « Rejoindre » (la home définitive reste MVP-07).
  - **Spike MVP-03 supprimé** comme prévu en clôture de MVP-05 : `LanServer`/`LanClient`, `DartIoLanServer`, `WebSocketLanClient`, les 2 écrans de debug LAN et leurs 3 fichiers de test, ainsi que le bloc l10n `lanDebug`. `local_ip.dart` reste (utilisé par le serveur hôte). Le cas R7 qu'ils couvraient est repris par le test « hôte injoignable → timeout typé ».
  - Règles tranchées en cours de route : un refus **définitif** (token invalide = QR périmé d'une session redémarrée) coupe court à la reconnexion, alors qu'une **session pleine** continue d'être retentée — une place peut se libérer ; `join()` sur une **autre** session oublie l'identité et la file d'envoi ; `leave()` reste réutilisable (rescan) et seul `dispose()` ferme le flux d'événements.
  - Deux défauts trouvés par les tests : `_handleClosed` programmait une reconnexion **en plus** de la boucle de backoff quand un socket tombait pendant une tentative (essais doublés) → seul l'appelant de la tentative décide de la suite ; et le panneau bas de l'écran de scan portait ses `ListTile` dans un `ColoredBox`, ce qui masque les effets d'encre au tap (assertion Flutter) → `Material`.
  - Constat honnête consigné : un message émis dans les quelques millisecondes entre la coupure physique et sa **constatation** part sur un tuyau mort, et TCP ne permet pas de le savoir. La file garantit l'acheminement à partir du moment où la coupure est constatée ; les segments réellement perdus relèvent des arrivées tardives de MVP-09/11.
  - Plateforme : `NSBonjourServices` (`_notalone._tcp`) dans l'Info.plist iOS — depuis iOS 14 un service absent de cette liste est invisible. Android n'a rien à ajouter, `bonsoir_android` déclare lui-même `INTERNET` et `CHANGE_WIFI_MULTICAST_STATE`.
  - Vérifié : analyze 0 issue, **220/220 tests verts**. Intégration du client contre un `DartIoHostServer` réel (12 cas) dont la coupure réseau rejouée par un **relais TCP** qui détruit les connexions en cours sans changer d'adresse : reconnexion transparente avec même `participantId` et sans doublon dans le registre, file d'envoi acheminée, abandon en fin de backoff, QR périmé. Couverture : `join_viewmodel` 100 %, `web_socket_guest_client` 95 %, `host_lobby_viewmodel` 95 %, `discovered_session` 96 %, `guest_client` 93 %. `bonsoir_session_discovery` à 0 % — platform channels non exécutables en CI, comme `silero_vad_service` et `record_mic_datasource` ; toute la logique qu'il porte (mapping du TXT record) est en `domain/` et testée.
  - Build `apk --debug` passé pour valider l'intégration du plugin natif. Il révèle un avertissement **préexistant, pas introduit par MVP-06** : trois plugins appliquent encore le Kotlin Gradle Plugin (`bonsoir_android`, `flutter_onnxruntime`, `mobile_scanner`), ce qu'une future version de Flutter refusera. À surveiller à l'occasion d'une montée de version — rien à faire aujourd'hui.
  - Reste à valider par Rayan sur 2 téléphones réels : parcours « scanner → connecté » **< 10 s** (chronométrer), coupure WiFi de 5 s → reprise transparente, et **découverte mDNS** quand le scan échoue (aucune de ces trois choses n'est vérifiable hors appareil).

### MVP-07 — Onboarding minimal et écran d'accueil

- **Statut** : ✅ fait
- **Dépend de** : MVP-01
- **Objectif** : premier lancement = saisie du prénom (persisté `shared_preferences`), puis home à 2 boutons : « Nouvelle conversation » / « Rejoindre ». Permissions demandées contextuellement (micro au premier join/host, caméra au premier scan) avec une phrase d'explication. Prénom modifiable dans `settings/`.
- **Critères d'acceptation** : lancements suivants → home direct ; refus de permission → écran d'explication avec lien réglages système, pas de crash ; conforme UX doc 01 §3.
- **Tests** : unitaires ViewModel onboarding ; widget tests home + refus de permission (permission service mocké derrière interface `domain/`).
- **Manuel (Rayan)** : —
- **Réalisé** (20/07/2026) :
  - Décisions validées avec Rayan avant de coder : (1) **`permission_handler` 12.0.3** plutôt que `record.hasPermission()` + `app_settings` — un seul package pour micro et caméra, il distingue le refus simple du refus définitif et sait ouvrir les réglages système ; vérifié avant de l'adopter que `permission_handler_apple` ≥ 9.4.8 (résolu en 9.4.10) supporte **Swift Package Manager** et déduit les permissions compilées des clés `NS…UsageDescription` de l'Info.plist — pas de retour au Podfile, dont MVP-02 avait montré qu'il cassait le build iPhone ; (2) micro demandé **à l'entrée du salon pour l'hôte, à la confirmation du prénom pour l'invité** (lettre du doc 01 §3) ; (3) **refus du micro non bloquant** — l'hôte est le lecteur, il doit pouvoir tenir la conversation et lire le transcript sans capter sa propre voix ; (4) **refus de la caméra → repli mDNS** « Chercher sur le réseau » : le parcours invité reste possible sans jamais accorder la caméra.
  - `onboarding/domain/` : `UserProfileRepository` (le prénom, seule donnée personnelle du MVP), `PermissionService` (`AppPermission`, `AppPermissionStatus` — préfixés `App` pour ne pas collisionner avec le `PermissionStatus` du package dans `data/`), `ProfileStorageFailure`/`PermissionUnavailableFailure`. `onboarding/data/` : `SharedPreferencesUserProfileRepository` (clé `user.name`, prénom vide = pas encore saisi) et `PermissionHandlerService` (`restricted` traité comme refus définitif : l'utilisateur ne peut pas l'accorder depuis l'app).
  - `onboarding/presentation/` : `AppRootViewModel` (aiguillage du démarrage), `OnboardingView`/`ViewModel`, `PermissionGateView`/`ViewModel` + la fabrique `permissionGate` qui **n'ouvre l'écran que si la permission manque** — au deuxième passage l'invité ne voit rien, ce qui préserve les 10 s du doc 01 §8. `session/presentation/` : `HomeView`/`HomeViewModel` (les écrans ouverts depuis la home passent par un `HomeDestinations` injecté, sinon l'accueil serait intestable sans serveur WebSocket ni caméra). `settings/presentation/` : le prénom seul, MVP-13 y ajoutera moteur STT et taille de police.
  - **Aucun `Platform.isIOS` pour distinguer les refus** : iOS n'annonce pas toujours qu'il ne redemandera plus, donc l'écran affiche « Réessayer » quand le statut le permet et **toujours** « Ouvrir les réglages » dès le premier refus. Vrai sur les deux OS sans code par plateforme (règle 7).
  - Promesse de MVP-06 tenue : `AppDependencies.provisionalName` supprimé, le prénom persisté circule jusqu'aux parcours hôte et invité **sans que `JoinViewModel` ni `HostLobbyViewModel` changent**. `JoinView` gagne seulement deux paramètres de vue (`showScanner`, `microphoneGate`). `shared_preferences` promu de `dev_dependencies` en dépendance réelle (il n'y était que par easy_localization).
  - Rien à ajouter côté plateforme : `NSMicrophoneUsageDescription`/`NSCameraUsageDescription` datent de MVP-02/03, `RECORD_AUDIO` du manifeste principal, `CAMERA` vient de celui de `mobile_scanner`.
  - Piège retrouvé en test : `app_test` montait des écrans vides dès son deuxième test — c'est le chargement asynchrone d'easy_localization déjà documenté dans `test/helpers/localized_app.dart`. Le chargeur FR préchargé y est désormais exposé (`frenchLoader`) pour les tests qui montent l'app entière.
  - Vérifié : analyze 0 issue, **280/280 tests verts** (220 avant). Couverture : `permission_gate` 100 %, `app_root_viewmodel` 100 %, `onboarding_viewmodel` 100 %, `home_viewmodel` 100 %, `settings_viewmodel` 100 %, `permission_gate_view` 100 %, `home_view` 96 %, `settings_view` 95 %, `shared_preferences_user_profile_repository` 64 % (les branches d'erreur exigeraient un stockage qui échoue), `permission_handler_service` 0 % — platform channels non exécutables en CI, comme `bonsoir_session_discovery` et `silero_vad_service`. Le critère « lancements suivants → home direct » est couvert bout en bout dans `app_test`.
  - Build `apk --debug` passé : `permission_handler_android` n'entre pas dans l'avertissement KGP préexistant (toujours `bonsoir_android`, `flutter_onnxruntime`, `mobile_scanner`).
  - Reste à constater sur appareils réels (aucun dialogue système ne se déclenche en widget test) : l'apparition effective des demandes micro et caméra au bon moment, et le bouton « Ouvrir les réglages » qui ouvre bien la fiche de l'app sur iOS et Android.

### MVP-08 — Pipeline de capture industrialisé (invité)

- **Statut** : ✅ fait
- **Dépend de** : MVP-02, MVP-04
- **Objectif** : transformer le spike MVP-02 en `capture/` propre : `CaptureSpeechUseCase` orchestrant mic → VAD → filtre énergie (seuil dans `VadConfig`) → émission de `SpeechSegment` horodatés. Capture maintenue écran verrouillé : foreground service `microphone` Android (+ demande d'exemption batterie), `UIBackgroundModes: audio` + gestion des interruptions `AVAudioSession` iOS → événements `mic_status`.
- **Critères d'acceptation** : 30 min de capture écran verrouillé sans interruption sur les 2 OS ; un appel entrant émet `mic_status: interrupted` puis reprise auto ; segments < 15 s (découpe forcée au-delà) ; aucune donnée audio écrite sur disque.
- **Tests** : unitaires use case (fixtures de buffers : silence/parole/voix faible) ; test manuel scripté des interruptions (checklist dans la tâche).
- **Manuel (Rayan)** : exécuter la checklist interruptions sur les 2 OS (appel entrant, notification, verrouillage, 30 min).
- **Réalisé** (20/07/2026) :
  - Décisions validées avec Rayan avant de coder : (1) foreground service Android via `flutter_foreground_task` 9.2.2 — **décision renversée en cours de tâche, voir ci-dessous** ; (2) filtre énergie traité en **plancher de bruit à −45 dBFS**, sous les −39 dBFS mesurés à 1,5 m en MVP-02 : il n'écarte que ce qui est plus faible qu'une voix à bout de table, l'arbitrage de proximité restant le métier de la dédup MVP-11 ; (3) **pré-roll de 200 ms** joint au segment, sans quoi le STT de MVP-10 reçoit une première syllabe rognée ; (4) `capture/` émet un **événement domaine `CaptureStatus`** et non le DTO `mic_status` — la traduction vers le fil et le `batteryPct` reviennent à MVP-13, `capture/` n'importe jamais `session/`.
  - **Trois constats d'exploration qui ont réduit le périmètre** : `record` gère déjà les interruptions **des deux côtés** (`AVAudioSession.interruptionNotification` sur iOS, `AudioFocusRequest` sur Android) dès qu'on passe `AudioInterruptionMode.pauseResume`, et les expose via `onStateChanged()` → **aucun platform channel maison** pour le `mic_status` ; iOS n'a besoin que de `UIBackgroundModes: audio`, la session audio active de `record` faisant le reste ; seul Android manquait de tout (`record_android` ne déclare que `RECORD_AUDIO`).
  - `capture/domain/` : `SpeechSegment` (horodaté **epoch**, porte ses samples en mémoire pour MVP-10), `CaptureStatus`, `BackgroundCaptureGuard`, `CaptureSpeechUseCase` (le pipeline complet), `MicAudioSource` gagne un `Stream<MicSourceState>`, `VadConfig` gagne `preRollMs`/`maxSegmentMs`/`minSegmentEnergyDbfs`, `SpeechSegmentBounds` devient `RawSpeechSegment` (il ne porte plus que des bornes : le buffer audio s'y ajoute).
  - **Renversement assumé (validé par Rayan en cours de tâche)** : `flutter_foreground_task` n'expose **qu'un podspec**, ni en 9.2.2 ni en 10.0.0 — aucun support de Swift Package Manager, et le package déclare une plateforme iOS. Sa seule présence dans le graphe a fait régénérer un `ios/Podfile` et réintroduit les `#include Pods-Runner` dans les xcconfigs, c'est-à-dire exactement la double intégration CocoaPods/SPM que MVP-02 avait dû quitter après le « sandbox is not in sync with the Podfile.lock » sur l'iPhone de Rayan. Le package a donc été retiré au profit d'un **service Kotlin maison** (`CaptureForegroundService.kt` + `MethodChannel` dans `MainActivity.kt`, ~130 lignes, sans dépendance androidx) : Android-only par nature, iOS reste 100 % SPM. L'interface `BackgroundCaptureGuard` de `domain/` a tenu sa promesse — **seul `foreground_service_capture_guard.dart` a changé**, ni le domaine, ni les tests, ni l'écran.
  - `capture/data/` : `RecordMicDatasource` relaie les états du recorder ; `ForegroundServiceCaptureGuard` (MethodChannel `notalone/background_capture`) + `background_capture_guard_factory` — **seul fichier du projet qui distingue Android d'iOS** pour la capture (règle 7), iOS recevant un garde neutre. `capture/presentation/` : `CaptureView`/`CaptureViewModel`.
  - **Spike MVP-02 supprimé** comme annoncé : `vad_debug_view`/`viewmodel`, leur test et le bloc l10n `vadDebug`, remplacés par l'écran « Mon micro » (état du micro, coupure manuelle, prises de parole captées) — c'est aussi lui qui permet de dérouler la checklist d'interruptions sur appareil réel.
  - Buffer audio du segment volontairement **plus large que ses bornes** : pré-roll en tête, silence de clôture en queue (un STT transcrit mieux une phrase non rognée aux deux bouts), alors que `tStartMs`/`tEndMs` restent strictement ceux de la parole — c'est sur eux que la dédup mesurera le chevauchement.
  - **Défaut trouvé en écrivant les tests, et qui aurait mordu en production** : le segmenteur compte des samples, or il n'en arrive aucun pendant un appel téléphonique — sans correction, tout ce qui suit une interruption aurait été daté en retard de la durée de l'appel. Le use case **ré-ancre son origine epoch** à chaque reprise (et remet à zéro segmenteur et VAD). Test de non-régression : interruption, +2 min d'horloge, reprise, le segment suivant est daté de l'heure réelle.
  - Second défaut corrigé en cours de route : `stop()` attendait la fin de la boucle `await for`, donc **la fin de la capture dépendait du producteur** — un micro qui ne referme pas son flux aurait figé l'arrêt. Remplacé par une souscription explicite mise **en pause pendant l'inférence** (contre-pression : sans elle, un VAD plus lent que le micro laisse les frames s'empiler), annulée par `stop()`/`setMuted()`/`dispose()`.
  - Piège d'environnement consigné pour les tâches suivantes : sous l'horloge simulée de `testWidgets`, la chaîne asynchrone qui suit un `StreamSubscription.cancel()` **ne progresse plus** (reproductible en 10 lignes sans code du projet). Les widget tests qui tapent un bouton annulant une souscription passent par `tester.runAsync` — helper `tapAndRun` dans `capture_view_test`.
  - Plateforme — Android : `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_MICROPHONE` (Android 14+), `POST_NOTIFICATIONS` (Android 13+), `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` + déclaration du service en `foregroundServiceType="microphone"`. iOS : `UIBackgroundModes: audio`.
  - Vérifié : analyze 0 issue, **326/326 tests verts** (280 avant, moins les 5 du spike retiré). Couverture : `capture_viewmodel` 100 %, `speech_segment` 100 %, `vad_config` 100 %, `speech_segmenter` 99 %, `capture_speech_use_case` 98 %, `capture_view` 95 % ; `record_mic_datasource`, `silero_vad_service` et `foreground_service_capture_guard` à 0 % — platform channels non exécutables en CI, comme `bonsoir_session_discovery` et `permission_handler_service`. Fixtures de buffers dans `test/fixtures/audio_fixtures.dart` (voix proche −6 dBFS, voix lointaine −34 dBFS, bruit de salle −54 dBFS).
  - « Aucune donnée audio écrite sur disque » vérifié par construction : `record` est utilisé en `startStream` (jamais `start(path:)`) et le seul `dart:io` de `capture/` est le `Platform.isAndroid` de la fabrique — aucune API fichier.
  - Build `apk --debug` passé (le service Kotlin compile). L'avertissement KGP reste celui d'avant la tâche — `bonsoir_android`, `flutter_onnxruntime`, `mobile_scanner` : **aucune dépendance ajoutée au projet par MVP-08**. Côté iOS, `git status` ne montre que le `UIBackgroundModes` de l'Info.plist : ni Podfile, ni include CocoaPods.
  - Reste à constater par Rayan sur appareils réels (rien de tout cela ne se simule) : les **30 min écran verrouillé** sur les 2 OS, l'**appel entrant** → statut interrompu puis reprise automatique, la notification persistante Android (le service maison n'a jamais tourné sur un vrai téléphone) et la demande d'exemption batterie. Le build iPhone est aussi à refaire une fois, pour confirmer que rien n'a ramené CocoaPods.

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
