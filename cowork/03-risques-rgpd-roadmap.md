# 03 — Risques, RGPD, roadmap

## 1. Risques techniques

| # | Risque | Impact | Mitigation |
|---|---|---|---|
| R1 | Batterie : capture + VAD 2 h épuisent les téléphones invités | Abandon de l'app | VAD léger (Silero ~1 Mo), pas d'écran allumé invité, mesure batterie dans MVP-15 ; seuil d'alerte à l'hôte |
| R2 | Cross-talk résiduel malgré filtres énergie + dédup | Faux messages, confiance rompue | Calibration terrain (MVP-15) ; consigne « TV coupée » ; vérification locuteur en v1 si taux > 5 % |
| R3 | TV/musique captée par le téléphone le plus proche (non dédupliquable) | Messages fantômes | Assumé au MVP (consigne d'usage) ; réglé en v1 par l'empreinte vocale |
| R4 | Qualité STT natif Android très variable selon OEM | Transcript médiocre pour certains invités | Option cloud par invité ; matrice d'appareils testés (MVP-15) |
| R5 | OS coupe la capture (appel, optimisation batterie OEM) | Trous silencieux dans le transcript | `mic_status` temps réel + alerte hôte ; foreground service + exemption batterie Android |
| R6 | Latences STT hétérogènes → transcript désordonné | Illisible | Sync horloge + buffer de réordonnancement 1,5 s (MVP-09) |
| R7 | WiFi domestique instable / isolation AP (les clients ne se voient pas) | Session impossible | Détection à la connexion + message clair (« activez le partage de connexion de l'hôte ») ; hotspot de l'hôte comme plan B documenté |
| R8 | Review App Store : background audio à justifier | Rejet store (v1) | Argumentaire accessibilité préparé, démo vidéo, catégorie accessibilité |

## 2. RGPD et légal

Positionnement : **privacy by design radical** — c'est un argument produit autant qu'une contrainte.

- **Audio** : jamais stocké, jamais transmis (le texte seul transite, en LAN). À écrire tel quel dans la politique de confidentialité.
- **Transcript** : éphémère par défaut, effacé partout à la fin de session (`session_end`). Sauvegarde (v1) = opt-in **unanime** des participants.
- **MVP sans biométrie** : aucune empreinte vocale → pas de donnée sensible article 9 au MVP.
- **v1 — empreinte vocale = donnée biométrique (article 9 RGPD)** : consentement explicite dédié à l'enrôlement, stockage **local uniquement** (jamais synchronisé), suppression en un geste dans les réglages, écran d'information clair.
- **Enregistrement de conversations** : l'app affiche à chaque participant qu'il rejoint une session transcrite (le scan du QR vaut information ; l'écran de join le rappelle). Les non-participants ne sont pas captés par construction (filtres).
- Prénom : donnée personnelle minimale, stockée localement.
- **À faire valider par un juriste avant publication stores (tâche manuelle Rayan, v1)** : politique de confidentialité, qualification non-dispositif médical, mentions stores.

## 3. Roadmap

```
Phase 0 — Socle + spikes de dérisquage   MVP-01 → MVP-03 (~2 semaines)
   Prouver : VAD temps réel on-device + session LAN 2 téléphones.
   Décision go/no-go technique ici, avant d'investir le reste.

Phase 1 — Chaîne complète 1→N         MVP-04 → MVP-11 (~6-8 semaines)
   Session, capture, STT, fusion, transcript UI.
   Jalon : « 3 téléphones, une conversation lisible ».

Phase 2 — Solidification              MVP-12 → MVP-15 (~3 semaines)
   UI transcript, supervision, réglages, moteur cloud, calibration terrain.
   Jalon : critère de succès MVP atteint sur repas réel de 6.

Phase 3 — v1 publiable                V1-01 → V1-10 (~8-10 semaines)
   Vérification locuteur, résumé IA, RGPD complet, stores.
```

Estimations pour un développement assisté par IA à temps partiel ; à recaler après la Phase 0.

## 4. Plan de test transverse

- **Unitaires (continu)** : tout `domain/` — dédup, réordonnancement, protocole, use cases. Objectif ≥ 90 % sur `transcript/domain` et `session/domain`.
- **Widget/golden (continu)** : transcript_view (tailles XL, contrastes), états d'erreur.
- **Intégration sur appareils (à chaque phase)** : 2 vrais téléphones minimum (1 iOS + 1 Android), session 30 min.
- **Test cross-talk dédié (MVP-15)** : protocole écrit — 2 puis 4 personnes autour d'une table, phrases scriptées simultanées, mesure du taux de doublons et de faux messages.
- **Test terrain famille (MVP-15, tâche manuelle Rayan)** : repas réel, grille d'observation (lisibilité, latence ressentie, batterie, incidents), débrief avec le père.
