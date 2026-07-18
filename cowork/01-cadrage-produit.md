# 01 — Cadrage produit : NotAlone

> Application mobile Flutter de transcription de conversations de groupe pour personnes sourdes et malentendantes.
> Cadrage validé le 18/07/2026. Ce document est la référence produit ; il ne se modifie qu'avec l'accord de Rayan.

## 1. Problème

Une personne sourde ou malentendante en repas de groupe ne perçoit qu'un brouhaha. Les solutions existantes (Ava, Google Live Transcribe, Live Captions OS) reposent sur **un seul micro** : en environnement bruyant multi-locuteurs, la diarisation échoue et l'attribution des propos est peu fiable. Cas fondateur : le père de Rayan, quasiment sourd, exclu des conversations aux repas de famille.

## 2. Idée clé (différenciateur)

**Un micro par locuteur.** Chaque convive capte sa propre voix avec son téléphone :

- flux audio propre (voix proche et forte), pas de diarisation nécessaire ;
- attribution par construction : le téléphone = la personne ;
- deux personnes parlant simultanément = deux flux propres (là où un micro unique échoue) ;
- fusion en temps réel en un fil type messagerie sur le téléphone du lecteur ;
- **100 % réseau local** : fonctionne sans internet (maison, restaurant, étranger).

## 3. Expérience utilisateur cible (priorité absolue : la fluidité)

L'app doit être utilisable par toute la famille sans explication. Deux parcours, aucun compte, aucune configuration :

**Créer** : j'ouvre l'app → « Nouvelle conversation » → un QR code s'affiche → les autres le scannent → je vois la conversation s'écrire.

**Rejoindre** : j'ouvre l'app → « Rejoindre » → je scanne le QR code → (première fois seulement : je tape mon prénom + j'accorde le micro) → je pose mon téléphone → c'est tout.

Règles UX qui en découlent :

- le prénom n'est demandé qu'une fois (persisté localement), modifiable dans les réglages ;
- les permissions ne sont demandées qu'au moment où elles servent, avec une phrase d'explication ;
- rejoindre une session : **< 30 secondes** la première fois, **< 10 secondes** ensuite ;
- aucune création de compte, aucun serveur distant, aucune donnée qui quitte le réseau local ;
- l'invité peut verrouiller son écran : la capture continue.

## 4. Rôles

| Rôle | Description |
|---|---|
| **Hôte / lecteur** | Crée la session, héberge le serveur local sur son téléphone, lit le transcript (gros caractères). Typiquement la personne malentendante. |
| **Invité** | Scanne le QR, capte et transcrit sa propre voix, envoie le texte à l'hôte. N'interagit plus ensuite. |

## 5. Personas

- **Le lecteur** (le père) : suivre qui parle et de quoi, en temps réel, lisiblement.
- **Le convive** : zéro friction, zéro effort après le scan.
- **L'organisateur** (Rayan) : installer, expliquer en une phrase, diagnostiquer (micro coupé, batterie).

## 6. Décisions actées

| Sujet | Décision | Motif |
|---|---|---|
| Framework | Flutter iOS + Android | Cross-platform, compétence porteur |
| Architecture | Clean Architecture + MVVM **ChangeNotifier natif** (pas de Riverpod) | Choix de Rayan ; suit le guide officiel Flutter |
| STT | Hybride : on-device natif par défaut, cloud en option | Coût nul par défaut, qualité en option, moteurs interchangeables |
| Sync | Réseau local : hôte = serveur WebSocket, QR code + mDNS | Zéro internet requis, différenciateur |
| Pipeline audio | Capture brute maison → VAD → segments courts → STT | Contourne limite 1 min iOS et timeout 5 s Android |
| Anti-cross-talk MVP | Seuil d'énergie + déduplication hôte | Suffisant avec consigne « TV coupée » |
| Vérification locuteur (biométrie) | **v1**, si les tests MVP montrent trop de faux messages | MVP sans donnée biométrique = RGPD allégé |
| Résumé IA du sujet | v1 | MVP valide d'abord la chaîne de transcription |
| Persistance | Éphémère par défaut ; audio jamais stocké ni transmis | Confiance, RGPD |
| Convives sans smartphone | Hors périmètre (réévalué post-v1) | Simplicité |
| Mode invité web | Non : app obligatoire | Fiabilité de la capture |

## 7. Périmètres

### MVP (distribution TestFlight / APK famille)
1. Session locale hôte/invités : QR + mDNS, 8 invités max.
2. Pipeline capture → VAD → filtre énergie → STT on-device FR (cloud en réglage optionnel).
3. Fusion hôte : horloge synchronisée, réordonnancement, déduplication cross-talk.
4. Transcript accessible : bulles prénom + couleur, tailles XL, auto-scroll intelligent, filtre par locuteur.
5. Supervision des micros côté hôte (actif / interrompu / batterie faible / déconnecté).
6. Éphémère strict. Aucune persistance du transcript.

### v1 (publication stores)
Vérification locuteur (enrôlement vocal + consentement biométrique), résumé IA du sujet en cours, dictionnaire personnalisé, sauvegarde opt-in unanime + export, mode miroir (plusieurs lecteurs), localisation FR/EN, RGPD complet, fiches stores.

### v2 (pistes non engagées)
Serveur relais pour sessions distantes, traduction en direct, micro d'appoint pour non-équipés, support tablette lecteur.

### Hors périmètre (acté)
Convives sans smartphone, mode web, tout stockage ou transmission d'audio brut, compte utilisateur, usage réunion professionnelle. L'app n'est **pas un dispositif médical** (formulation marketing à surveiller).

## 8. Exigences non fonctionnelles

| Exigence | Cible MVP |
|---|---|
| Latence parole → affichage | < 2 s on-device, < 3 s cloud |
| Doublons cross-talk affichés | < 5 % des messages |
| Autonomie invité en session | ≥ 2 h sans charge (téléphone milieu de gamme) |
| Tenue de session | 2 h sans interruption de capture (hors événements OS) |
| Rejoindre une session | < 30 s (1ʳᵉ fois), < 10 s ensuite |
| Langue | FR (architecture prête pour multi-langues) |

## 9. Critère de succès du MVP

Repas réel de 6 personnes pendant 1 h : le lecteur identifie **qui parle et de quel sujet il s'agit** ≥ 80 % du temps, doublons < 5 %, aucune capture tombée sans alerte à l'hôte.
