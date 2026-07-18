# Tâches V1 — publication stores

> Exécuter avec `/dev-task V1-XX`. Prérequis global : MVP terminé (MVP-15 ✅), décision vérification locuteur prise.
> Statuts : ⬜ à faire · 🟧 en cours · ✅ fait.

---

### V1-01 — Enrôlement vocal et consentement biométrique

- **Statut** : ⬜ à faire
- **Dépend de** : MVP-15 (et décision « vérification locuteur : oui » issue des mesures terrain)
- **Objectif** : parcours d'enrôlement (~20 s de lecture guidée) → empreinte vocale stockée **localement uniquement** ; écran de consentement biométrique dédié (RGPD art. 9, cf. doc 03 §2) ; suppression de l'empreinte en un geste dans les réglages ; enrôlement optionnel (refus = pipeline MVP sans filtre locuteur).
- **Critères d'acceptation** : l'empreinte ne transite jamais sur le réseau (vérifiable dans le protocole) ; suppression effective vérifiée ; refus de consentement → app pleinement fonctionnelle ; textes de consentement relus par Rayan.
- **Tests** : unitaires ViewModel enrôlement (états, refus, suppression) ; widget tests du parcours ; vérification protocolaire (aucun DTO ne contient d'embedding).
- **Manuel (Rayan)** : valider les textes de consentement ; tester l'enrôlement avec 3 voix différentes de la famille.

### V1-02 — Vérification du locuteur dans le pipeline

- **Statut** : ⬜ à faire
- **Dépend de** : V1-01
- **Objectif** : interface `SpeakerVerifier` dans `capture/domain/` + implémentation on-device (Picovoice Eagle, ou modèle ECAPA/ONNX si licence Picovoice inadaptée — décision en début de tâche avec Rayan) ; chaque segment reçoit un score de similarité avec l'empreinte du propriétaire ; sous le seuil → segment marqué `suspect` et exclu de l'attribution (le filtre 3 de dédup l'utilise en départage) ; règle la captation TV/musique (R3).
- **Critères d'acceptation** : sur le protocole cross-talk de MVP-15 rejoué **avec TV allumée**, faux messages < 2 % ; faux rejets du propriétaire < 5 % (voix normale) ; latence ajoutée < 100 ms/segment ; batterie : impact < 10 % vs MVP.
- **Tests** : contrat `SpeakerVerifier` avec fake ; fixtures multi-voix ; rejeu automatisé des scénarios MVP-11 enrichis du score locuteur.
- **Manuel (Rayan)** : créer le compte Picovoice si retenu (clé en `--dart-define`) ; rejouer le protocole terrain avec TV.

### V1-03 — Résumé IA « De quoi parle-t-on ? »

- **Statut** : ⬜ à faire
- **Dépend de** : MVP-15
- **Objectif** : bouton sur l'écran lecteur → résumé 2–3 phrases des 2 dernières minutes du fil. Interface `SummaryService` dans `transcript/domain/` + implémentation LLM cloud (fournisseur au choix de Rayan en début de tâche, clé en `--dart-define`) ; grisé sans internet ; le résumé est éphémère et n'est jamais stocké ; seul le texte des 2 dernières minutes est envoyé (fenêtre minimale, pas d'identifiants au-delà des prénoms).
- **Critères d'acceptation** : résumé < 4 s après appui ; panne/timeout → message discret, jamais de blocage UI ; l'envoi est strictement limité à la fenêtre ; opt-out global dans les réglages (« jamais d'envoi cloud »).
- **Tests** : unitaires fenêtre + prompt building ; contrat `SummaryService` avec fake ; widget test des états (chargement/succès/erreur/hors-ligne).
- **Manuel (Rayan)** : choisir le fournisseur LLM + créer la clé ; juger la qualité des résumés sur un vrai repas.

### V1-04 — Dictionnaire personnalisé par session

- **Statut** : ⬜ à faire
- **Dépend de** : MVP-14
- **Objectif** : liste de mots par session (prénoms, surnoms, lieux) éditable par l'hôte avant/pendant la session, diffusée aux invités (nouveau message protocole `custom_vocab`, version protocole incrémentée), injectée dans les moteurs qui le supportent (Gladia ; natif : appliqué en post-correction simple par distance d'édition).
- **Critères d'acceptation** : un surnom du dictionnaire mal transcrit par le natif est corrigé en post-traitement ; les invités reçoivent le dictionnaire à la connexion et à chaque mise à jour ; compat ascendante (invité MVP sans support → ignore le message).
- **Tests** : unitaires post-correction (vrais/faux positifs) ; round-trip protocole ; intégration hôte→invité.
- **Manuel (Rayan)** : constituer le dictionnaire famille réel et mesurer l'amélioration.

### V1-05 — Sauvegarde opt-in unanime et export

- **Statut** : ⬜ à faire
- **Dépend de** : MVP-15
- **Objectif** : à la fin de session, l'hôte peut demander la conservation → requête de consentement envoyée à chaque invité (message protocole `save_consent`) ; **unanimité requise** ; si accordée, export texte (partage système iOS/Android) depuis le téléphone hôte uniquement ; sinon effacement standard.
- **Critères d'acceptation** : un seul refus (ou non-réponse < 60 s) → effacement partout ; le fichier exporté contient prénoms + horodatages + texte, rien d'autre ; l'invité voit clairement ce qu'il accepte.
- **Tests** : unitaires machine à états du consentement (accord/refus/timeout/déconnexion) ; intégration bout en bout ; round-trip protocole.
- **Manuel (Rayan)** : —

### V1-06 — Mode miroir (plusieurs lecteurs)

- **Statut** : ⬜ à faire
- **Dépend de** : MVP-15
- **Objectif** : tout invité peut ouvrir la vue transcript sur son propre téléphone : l'hôte diffuse `transcript_update` (entrées fusionnées post-dédup) aux clients qui s'y abonnent ; l'écran miroir réutilise `transcript_view` (mêmes réglages de taille locaux).
- **Critères d'acceptation** : miroir synchronisé < 1 s après l'hôte ; un miroir qui rejoint en cours de session reçoit l'historique ; `session_end` efface aussi les miroirs ; la capture de l'invité-miroir continue en parallèle.
- **Tests** : intégration hôte + 2 miroirs simulés (historique, rattrapage, effacement) ; unitaires ViewModel miroir.
- **Manuel (Rayan)** : —

### V1-07 — Localisation FR/EN et onboarding soigné

- **Statut** : ⬜ à faire
- **Dépend de** : MVP-15
- **Objectif** : externaliser toutes les chaînes (ARB, `flutter_localizations`), traduction EN, langue STT sélectionnable par session (FR/EN pour commencer) ; onboarding raffiné : 3 écrans max expliquant le concept (illustrations simples), demande de prénom intégrée, accessibilité vérifiée (lecteur d'écran, tailles système respectées).
- **Critères d'acceptation** : 0 chaîne en dur (lint dédié) ; app complète en EN ; VoiceOver/TalkBack parcourent l'onboarding et le home sans piège ; changement de langue sans redémarrage.
- **Tests** : test d'intégration linting des chaînes ; widget tests dans les 2 langues ; audit accessibilité manuel (checklist dans la tâche).
- **Manuel (Rayan)** : relire les textes FR/EN ; dérouler la checklist accessibilité avec VoiceOver.

### V1-08 — RGPD complet et pages légales

- **Statut** : ⬜ à faire
- **Dépend de** : V1-01, V1-03, V1-05
- **Objectif** : politique de confidentialité (privacy by design du doc 03 §2 : audio jamais stocké/transmis, éphémère par défaut, biométrie locale, envois cloud opt-in), écrans « vos données » dans les réglages (voir/supprimer : prénom, empreinte, réglages), registre des traitements (document interne), bannières de consentement là où nécessaire — et nulle part ailleurs.
- **Critères d'acceptation** : chaque affirmation de la politique est vérifiable dans le code (revue croisée doc↔code jointe à la tâche) ; suppression totale des données locales en un parcours ; formulations « non dispositif médical » vérifiées.
- **Tests** : tests des parcours de suppression ; revue croisée documentée.
- **Manuel (Rayan)** : **faire valider politique + mentions par un juriste** ; héberger la politique (URL requise par les stores).

### V1-09 — Préparation stores et CI de release

- **Statut** : ⬜ à faire
- **Dépend de** : V1-07, V1-08
- **Objectif** : identifiants d'app définitifs, icône + splash, fiches App Store / Play Store (FR/EN, angle accessibilité), captures d'écran, **argumentaire background audio pour la review Apple** (R8 : app d'accessibilité, démo vidéo), pipeline de release (GitHub Actions + fastlane : build signé, TestFlight / Play internal track).
- **Critères d'acceptation** : `main` taguée → build signé livré automatiquement sur les 2 tracks de test ; fiches complètes relues ; dossier de review Apple prêt (texte + vidéo).
- **Tests** : dry-run complet du pipeline ; installation des builds sur appareils vierges.
- **Manuel (Rayan)** : comptes développeur Apple (99 $/an) et Google Play (25 $) ; certificats/signing ; tournage de la vidéo démo ; soumission et suivi des reviews.

### V1-10 — Bêta élargie et durcissement

- **Statut** : ⬜ à faire
- **Dépend de** : V1-09
- **Objectif** : bêta TestFlight/Play (10–20 foyers, idéalement via associations de malentendants), collecte de retours structurée (formulaire), tri et correction des bugs bloquants/majeurs, décision de lancement public.
- **Critères d'acceptation** : ≥ 5 sessions réelles hors famille documentées ; 0 bug bloquant ouvert ; taux de sessions réussies (> 30 min sans incident) ≥ 80 % ; go/no-go lancement documenté.
- **Tests** : non-régression complète avant chaque build bêta ; rejeu du protocole cross-talk après chaque correction du pipeline.
- **Manuel (Rayan)** : recruter les bêta-testeurs (associations, forums) ; animer la bêta ; décider du lancement.
