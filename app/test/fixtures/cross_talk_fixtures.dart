/// Scénarios de repas scriptés pour la déduplication cross-talk
/// (cf. cowork/02-architecture.md §5.3).
///
/// **À relire par Rayan** (« Manuel » de MVP-11) : ces fixtures sont le seul
/// juge de la dédup tant que le test famille (MVP-15) n'a pas eu lieu. Si un
/// scénario ne ressemble pas à un vrai repas, c'est la dédup qui sera calibrée
/// de travers.
///
/// Conventions communes à tous les scénarios :
/// - les horodatages sont en millisecondes sur une horloge commune (les tests
///   qui veulent éprouver les écarts d'horloge décalent eux-mêmes) ;
/// - `energyDb` est du dBFS : **plus proche du micro = moins négatif**. Les
///   valeurs viennent des mesures de MVP-02 (voix à 1,5 m ≈ −39 dBFS, voix
///   proche ≈ −8 dBFS) ;
/// - les convives portent des prénoms pour que les scénarios se lisent.
library;

import 'package:notalone/features/transcript/domain/incoming_segment.dart';

const String papa = 'p-papa';
const String marie = 'p-marie';
const String luc = 'p-luc';
const String jeanne = 'p-jeanne';

/// Voix dans son propre téléphone, posé devant soi.
const double dbClose = -8;

/// Voix d'un convive assis en face, captée par mon téléphone.
const double dbFar = -32;

/// Voix d'un convive à l'autre bout de la table.
const double dbVeryFar = -41;

IncomingSegment segment({
  required String participantId,
  required String segmentId,
  required int tStartMs,
  required int tEndMs,
  required String text,
  required double energyDb,
  bool isFinal = true,
  String engine = 'ios_speech_analyzer',
}) => IncomingSegment(
  participantId: participantId,
  segmentId: segmentId,
  tStartMs: tStartMs,
  tEndMs: tEndMs,
  text: text,
  energyDb: energyDb,
  engine: engine,
  isFinal: isFinal,
);

/// **Cas fondateur du cross-talk.** Papa demande le sel ; son propre téléphone
/// le capte de près, celui de Marie assise en face le capte aussi, de loin et
/// avec une faute de reconnaissance (« sel » → « seul », l'erreur typique d'un
/// micro éloigné). Les VAD n'ouvrent pas au même instant : celui de Marie a
/// 180 ms de retard et coupe 220 ms plus tôt.
///
/// Attendu : **une seule entrée**, attribuée à Papa, avec le texte du micro
/// proche.
List<IncomingSegment> samePhraseTwoMics() => [
  segment(
    participantId: papa,
    segmentId: 'papa-sel',
    tStartMs: 10000,
    tEndMs: 12400,
    text: 'Tu peux me passer le sel ?',
    energyDb: dbClose,
  ),
  segment(
    participantId: marie,
    segmentId: 'marie-echo-sel',
    tStartMs: 10180,
    tEndMs: 12180,
    text: 'tu peux me passer le seul',
    energyDb: dbFar,
  ),
];

/// La même phrase captée par **trois** téléphones : à six autour d'une table,
/// c'est le cas courant, pas l'exception. Jeanne est à l'autre bout.
///
/// Attendu : **une seule entrée**, attribuée à Papa, portant la trace des deux
/// autres captations.
List<IncomingSegment> samePhraseThreeMics() => [
  ...samePhraseTwoMics(),
  segment(
    participantId: jeanne,
    segmentId: 'jeanne-echo-sel',
    tStartMs: 10240,
    tEndMs: 12300,
    text: 'tu peux me passer le sel',
    energyDb: dbVeryFar,
  ),
];

/// **Le piège inverse** : deux convives parlent en même temps, mais ne disent
/// pas la même chose. Le chevauchement est total, seul le texte les distingue.
///
/// Attendu : **deux entrées**. Les fusionner effacerait une vraie phrase —
/// c'est la faute la plus grave (doc 01 §9).
List<IncomingSegment> simultaneousDifferentPhrases() => [
  segment(
    participantId: marie,
    segmentId: 'marie-chaud',
    tStartMs: 20000,
    tEndMs: 22000,
    text: "Il fait chaud aujourd'hui",
    energyDb: dbClose,
  ),
  segment(
    participantId: luc,
    segmentId: 'luc-gratin',
    tStartMs: 20100,
    tEndMs: 22200,
    text: 'Je reprendrais bien du gratin',
    energyDb: dbClose,
  ),
];

/// Deux convives disent la **même chose** à vingt secondes d'intervalle — on
/// approuve beaucoup, à table. Rien ne se chevauche.
///
/// Attendu : **deux entrées**.
List<IncomingSegment> samePhraseFarApart() => [
  segment(
    participantId: marie,
    segmentId: 'marie-daccord',
    tStartMs: 30000,
    tEndMs: 31000,
    text: "Oui, je suis d'accord",
    energyDb: dbClose,
  ),
  segment(
    participantId: luc,
    segmentId: 'luc-daccord',
    tStartMs: 50000,
    tEndMs: 51000,
    text: "Oui, je suis d'accord",
    energyDb: dbClose,
  ),
];

/// La **même personne** qui se répète dans la foulée, captée par son seul
/// téléphone. Les deux segments se touchent presque et se ressemblent
/// beaucoup.
///
/// Attendu : **deux entrées**. Le cross-talk est par définition un énoncé
/// capté par *plusieurs* téléphones ; deux segments d'un même micro sont deux
/// prises de parole.
List<IncomingSegment> sameSpeakerRepeats() => [
  segment(
    participantId: papa,
    segmentId: 'papa-oui-1',
    tStartMs: 60000,
    tEndMs: 60600,
    text: 'Oui oui',
    energyDb: dbClose,
  ),
  segment(
    participantId: papa,
    segmentId: 'papa-oui-2',
    tStartMs: 60500,
    tEndMs: 61200,
    text: 'Oui oui',
    energyDb: dbClose,
  ),
];

/// Un repas complet, généré : [speakers] convives, chacun prenant la parole
/// toutes les [gapMs] millisecondes pendant [durationMs]. Chaque énoncé est
/// **aussi capté par le voisin de gauche**, de plus loin et avec une faute —
/// c'est le régime permanent d'une vraie table, pas un cas limite.
///
/// Les segments sont rendus dans l'ordre où l'hôte les reçoit : le doublon
/// lointain arrive après l'original, avec un retard réseau/STT variable.
List<IncomingSegment> scriptedMeal({
  required int speakers,
  required int durationMs,
  int gapMs = 8000,
  int firstSpeechMs = 1000,
}) {
  const phrases = [
    'On mange à quelle heure demain',
    "Il reste du pain dans la cuisine s'il t'en faut",
    'Je trouve que ce plat est vraiment réussi',
    'Tu as eu des nouvelles de ta soeur cette semaine',
    "Passe moi l'eau je t'en prie",
    'Le train de dimanche part en fin de matinée',
  ];
  final segments = <IncomingSegment>[];
  var index = 0;
  for (var tMs = firstSpeechMs; tMs < durationMs; tMs += gapMs) {
    final speaker = index % speakers;
    final neighbour = (speaker + 1) % speakers;
    final phrase = phrases[index % phrases.length];
    final startMs = tMs + speaker * 90;
    segments
      ..add(
        segment(
          participantId: 'p-$speaker',
          segmentId: 's-$index-proche',
          tStartMs: startMs,
          tEndMs: startMs + 2600,
          text: phrase,
          energyDb: dbClose,
        ),
      )
      ..add(
        segment(
          participantId: 'p-$neighbour',
          segmentId: 's-$index-lointain',
          // Le VAD du voisin ouvre plus tard et ferme plus tôt.
          tStartMs: startMs + 170,
          tEndMs: startMs + 2380,
          text: _misheard(phrase),
          energyDb: dbFar,
        ),
      );
    index++;
  }
  return segments;
}

/// Nombre d'énoncés réellement prononcés dans [scriptedMeal] — la moitié des
/// segments, l'autre moitié étant leurs doublons.
int scriptedMealUtterances({
  required int durationMs,
  int gapMs = 8000,
  int firstSpeechMs = 1000,
}) {
  var count = 0;
  for (var tMs = firstSpeechMs; tMs < durationMs; tMs += gapMs) {
    count++;
  }
  return count;
}

/// Ce qu'un micro lointain rend d'une phrase : le dernier mot fautif. Assez
/// pour faire chuter la similarité, pas assez pour en faire une autre phrase —
/// exactement la zone où la dédup doit trancher juste.
String _misheard(String phrase) {
  final words = phrase.split(' ');
  words[words.length - 1] = '${words.last}e';
  return words.join(' ').toLowerCase();
}
