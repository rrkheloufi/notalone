import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notalone/features/session/domain/participant.dart';
import 'package:notalone/features/session/domain/participant_supervision.dart';
import 'package:notalone/features/session/domain/protocol/session_message.dart';
import 'package:notalone/features/session/domain/supervision_config.dart';
import 'package:notalone/features/session/presentation/supervision_banner.dart';
import 'package:notalone/features/session/presentation/supervision_panel.dart';

import '../../../helpers/localized_app.dart';

ParticipantSupervision supervised({
  String id = 'g1',
  String name = 'Paul',
  MicStatusState? micState,
  int? batteryPct,
  bool isConnected = true,
  bool isHost = false,
}) => ParticipantSupervision.from(
  participant: Participant(
    id: id,
    name: name,
    colorIndex: 1,
    isHost: isHost,
    isConnected: isConnected,
  ),
  config: const SupervisionConfig(),
  micState: micState,
  batteryPct: batteryPct,
);

void main() {
  setUpAll(initLocalization);

  group('panneau du salon', () {
    testWidgets('micro actif : état et batterie en toutes lettres', (
      tester,
    ) async {
      await pumpLocalized(
        tester,
        Scaffold(
          body: SupervisionPanel(
            participants: [
              supervised(micState: MicStatusState.active, batteryPct: 76),
            ],
          ),
        ),
      );

      expect(find.text('Paul'), findsOneWidget);
      expect(find.textContaining('micro actif'), findsOneWidget);
      expect(find.textContaining('batterie 76 %'), findsOneWidget);
    });

    testWidgets('micro coupé : dit et montré', (tester) async {
      // La couleur ne porte jamais seule l'information (décision MVP-12) :
      // l'état est écrit, l'icône ne fait que le doubler.
      await pumpLocalized(
        tester,
        Scaffold(
          body: SupervisionPanel(
            participants: [
              supervised(micState: MicStatusState.muted, batteryPct: 76),
            ],
          ),
        ),
      );

      expect(find.textContaining('micro coupé'), findsOneWidget);
      expect(find.byIcon(Icons.mic_off), findsOneWidget);
    });

    testWidgets('batterie faible signalée comme telle', (tester) async {
      await pumpLocalized(
        tester,
        Scaffold(
          body: SupervisionPanel(
            participants: [
              supervised(micState: MicStatusState.active, batteryPct: 9),
            ],
          ),
        ),
      );

      expect(find.textContaining('batterie faible (9 %)'), findsOneWidget);
      expect(find.byIcon(Icons.battery_alert), findsOneWidget);
    });

    testWidgets('déconnecté : le reste devient du détail', (tester) async {
      await pumpLocalized(
        tester,
        Scaffold(
          body: SupervisionPanel(
            participants: [
              supervised(
                micState: MicStatusState.muted,
                batteryPct: 5,
                isConnected: false,
              ),
            ],
          ),
        ),
      );

      expect(find.text('déconnecté'), findsOneWidget);
      expect(find.byIcon(Icons.signal_wifi_off), findsOneWidget);
      expect(find.textContaining('batterie'), findsNothing);
    });

    testWidgets('rien reçu : le panneau ne prétend pas savoir', (tester) async {
      await pumpLocalized(
        tester,
        Scaffold(body: SupervisionPanel(participants: [supervised()])),
      );

      expect(find.text('micro : pas encore de nouvelles'), findsOneWidget);
    });

    testWidgets('l’hôte peut se couper le micro depuis sa ligne', (
      tester,
    ) async {
      var toggles = 0;
      await pumpLocalized(
        tester,
        Scaffold(
          body: SupervisionPanel(
            participants: [
              supervised(name: 'Rayan', isHost: true),
              supervised(),
            ],
            onToggleHostMute: () => toggles++,
          ),
        ),
      );

      expect(find.text('Rayan (toi)'), findsOneWidget);
      await tester.tap(find.byTooltip('Couper mon micro'));
      await tester.pumpAndSettle();

      expect(toggles, 1);
    });
  });

  group('bandeau du fil', () {
    testWidgets('une phrase, pas un code d’état', (tester) async {
      // « Le micro de Paul est coupé » est la formulation que l'objectif de
      // MVP-13 demande.
      await pumpLocalized(
        tester,
        Scaffold(
          body: SupervisionBanner(
            alerts: [supervised(micState: MicStatusState.muted)],
            onOpenPanel: () {},
          ),
        ),
      );

      expect(find.textContaining('Le micro de Paul est coupé'), findsOneWidget);
    });

    testWidgets('aucune alerte : le bandeau ne prend aucune place', (
      tester,
    ) async {
      await pumpLocalized(
        tester,
        Scaffold(
          body: SupervisionBanner(alerts: const [], onOpenPanel: () {}),
        ),
      );

      expect(find.byType(InkWell), findsNothing);
    });

    testWidgets('plusieurs alertes : la plus grave, puis le compte', (
      tester,
    ) async {
      await pumpLocalized(
        tester,
        Scaffold(
          body: SupervisionBanner(
            alerts: [
              supervised(micState: MicStatusState.active, batteryPct: 8),
              supervised(id: 'g2', name: 'Camille', isConnected: false),
            ],
            onOpenPanel: () {},
          ),
        ),
      );

      // Déconnecté prime sur batterie faible : c'est ce que l'hôte doit
      // traiter en premier.
      expect(
        find.textContaining("Camille n'est plus connecté"),
        findsOneWidget,
      );
      expect(find.textContaining('et 1 autre convive'), findsOneWidget);
    });

    testWidgets('le bandeau ramène au panneau', (tester) async {
      var opened = 0;
      await pumpLocalized(
        tester,
        Scaffold(
          body: SupervisionBanner(
            alerts: [supervised(micState: MicStatusState.muted)],
            onOpenPanel: () => opened++,
          ),
        ),
      );

      await tester.tap(find.byType(InkWell));
      await tester.pumpAndSettle();

      expect(opened, 1);
    });
  });
}
