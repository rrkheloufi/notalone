import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notalone/core/result/result.dart';
import 'package:notalone/features/session/domain/discovered_session.dart';
import 'package:notalone/features/session/domain/guest_client.dart';
import 'package:notalone/features/session/domain/protocol/session_close_codes.dart';
import 'package:notalone/features/session/domain/protocol/session_message.dart';
import 'package:notalone/features/session/domain/qr_session_payload.dart';
import 'package:notalone/features/session/domain/session_discovery.dart';
import 'package:notalone/features/session/domain/session_failure.dart';
import 'package:notalone/features/session/presentation/join_view.dart';
import 'package:notalone/features/session/presentation/join_viewmodel.dart';

import '../../../helpers/localized_app.dart';

const validPayload = QrSessionPayload(
  sessionName: 'Repas',
  host: '192.168.1.10',
  port: 40000,
  token: 'tok',
);

const discovered = DiscoveredSession(
  sessionName: 'Repas de Rayan',
  host: '192.168.1.11',
  port: 40001,
  token: 'tok2',
);

const identity = GuestSession(
  participantId: 'p1',
  colorIndex: 3,
  clockOffsetProbe: 1000,
);

final class _FakeGuestClient implements GuestClient {
  final StreamController<GuestClientEvent> _events =
      StreamController.broadcast();

  Result<GuestSession> joinResult = const Result.ok(identity);
  String? joinedName;

  @override
  GuestSession? session;

  @override
  Stream<GuestClientEvent> get events => _events.stream;

  @override
  Future<Result<GuestSession>> join({
    required QrSessionPayload session,
    required String name,
  }) async {
    joinedName = name;
    if (joinResult case Ok(value: final joined)) this.session = joined;
    return joinResult;
  }

  @override
  void send(SessionMessage message) {}

  @override
  Future<void> leave() async => session = null;

  @override
  Future<void> dispose() async {}

  void emit(GuestClientEvent event) => _events.add(event);
}

final class _FakeBrowser implements SessionBrowser {
  final StreamController<List<DiscoveredSession>> _sessions =
      StreamController.broadcast();

  @override
  Stream<List<DiscoveredSession>> get sessions => _sessions.stream;

  @override
  Future<Result<void>> start() async => const Result.ok(null);

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}

  void publish(List<DiscoveredSession> found) => _sessions.add(found);
}

/// Scanner factice : un bouton qui livre le contenu d'un QR. La vraie caméra
/// (`MobileScanner`) passe par un platform channel absent des widget tests —
/// d'où l'injection du constructeur de scanner dans `JoinView`.
QrScannerBuilder scannerBuilding(String raw) =>
    (context, onScanned) => Center(
      child: ElevatedButton(
        onPressed: () => onScanned(raw),
        child: const Text('scanner'),
      ),
    );

({JoinView view, _FakeGuestClient client, _FakeBrowser browser}) buildView({
  String scanned = '',
}) {
  final client = _FakeGuestClient();
  final browser = _FakeBrowser();
  return (
    view: JoinView(
      viewModel: JoinViewModel(
        client: client,
        browser: browser,
        initialName: 'Invité',
      ),
      scannerBuilder: scannerBuilding(
        scanned.isEmpty ? validPayload.encode() : scanned,
      ),
    ),
    client: client,
    browser: browser,
  );
}

void main() {
  setUpAll(initLocalization);

  testWidgets('scan → prénom pré-rempli → connecté', (tester) async {
    final (:view, :client, browser: _) = buildView();
    await pumpLocalized(tester, view);
    expect(
      find.text("Scanne le QR code affiché sur le téléphone de l'hôte"),
      findsOneWidget,
    );

    await tester.tap(find.text('scanner'));
    await tester.pumpAndSettle();

    expect(find.text('Repas'), findsOneWidget);
    expect(find.text('Ton prénom'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Invité'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Camille');
    await tester.tap(find.widgetWithText(FilledButton, 'Rejoindre'));
    await tester.pumpAndSettle();

    expect(client.joinedName, 'Camille');
    expect(find.text('Tu es dans la conversation, Camille'), findsOneWidget);
    expect(
      find.text('Tu peux poser ton téléphone. Parle normalement.'),
      findsOneWidget,
    );
  });

  testWidgets('QR illisible → l’invité reste sur le scanner avec le motif', (
    tester,
  ) async {
    final (:view, :client, browser: _) = buildView(scanned: 'pas un payload');
    await pumpLocalized(tester, view);

    await tester.tap(find.text('scanner'));
    await tester.pumpAndSettle();

    expect(find.text('scanner'), findsOneWidget, reason: 'toujours en scan');
    expect(find.textContaining('Payload QR invalide'), findsOneWidget);
    expect(client.joinedName, isNull);
  });

  testWidgets('refus de l’hôte → motif lisible sans jargon', (tester) async {
    final (:view, :client, browser: _) = buildView();
    client.joinResult = Result.err(
      JoinRefusedFailure(SessionCloseCodes.sessionFull),
    );
    await pumpLocalized(tester, view);

    await tester.tap(find.text('scanner'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Rejoindre'));
    await tester.pumpAndSettle();

    expect(find.text('La session est complète'), findsOneWidget);
    expect(find.text('Ton prénom'), findsOneWidget);
  });

  testWidgets('WiFi isolant (R7) → consigne de partage de connexion', (
    tester,
  ) async {
    final (:view, :client, browser: _) = buildView();
    client.joinResult = const Result.err(ConnectionTimeoutFailure());
    await pumpLocalized(tester, view);

    await tester.tap(find.text('scanner'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Rejoindre'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Connexion à l hôte expirée'), findsOneWidget);
  });

  testWidgets('une session trouvée en mDNS se rejoint d’un tap', (
    tester,
  ) async {
    final (:view, :client, :browser) = buildView();
    await pumpLocalized(tester, view);

    browser.publish([discovered]);
    await tester.pumpAndSettle();
    expect(find.text('Conversations trouvées sur le réseau'), findsOneWidget);

    await tester.tap(find.text('Repas de Rayan'));
    await tester.pumpAndSettle();

    expect(find.text('Ton prénom'), findsOneWidget);
  });

  testWidgets('coupure → écran de reconnexion numéroté', (tester) async {
    final (:view, :client, browser: _) = buildView();
    await pumpLocalized(tester, view);
    await tester.tap(find.text('scanner'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Rejoindre'));
    await tester.pumpAndSettle();

    client.emit(
      const GuestReconnecting(attempt: 2, delay: Duration(seconds: 2)),
    );
    // Deux pumps plutôt qu'un `pumpAndSettle` : l'écran de reconnexion tourne
    // en boucle (indicateur de progression), il ne se stabilise jamais.
    await tester.pump();
    await tester.pump();

    expect(find.text('Reconnexion… (essai 2)'), findsOneWidget);
  });

  testWidgets('fin de session par l’hôte → message et retour au scan', (
    tester,
  ) async {
    final (:view, :client, browser: _) = buildView();
    await pumpLocalized(tester, view);
    await tester.tap(find.text('scanner'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Rejoindre'));
    await tester.pumpAndSettle();

    client.emit(const GuestSessionEnded());
    await tester.pumpAndSettle();
    expect(find.text("L'hôte a terminé la conversation"), findsOneWidget);

    await tester.tap(find.text('Scanner à nouveau'));
    await tester.pumpAndSettle();
    expect(find.text('scanner'), findsOneWidget);
  });

  testWidgets('connexion perdue → motif affiché et rescan possible', (
    tester,
  ) async {
    final (:view, :client, browser: _) = buildView();
    await pumpLocalized(tester, view);
    await tester.tap(find.text('scanner'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Rejoindre'));
    await tester.pumpAndSettle();

    client.emit(const GuestConnectionLost(ConnectionTimeoutFailure()));
    await tester.pumpAndSettle();

    expect(find.textContaining('Connexion à l hôte expirée'), findsOneWidget);
    expect(find.text('Scanner à nouveau'), findsOneWidget);
  });
}
