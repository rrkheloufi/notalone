import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notalone/features/onboarding/domain/permission_service.dart';
import 'package:notalone/features/onboarding/presentation/permission_gate_view.dart';
import 'package:notalone/features/onboarding/presentation/permission_gate_viewmodel.dart';

import '../../../helpers/fake_permission_service.dart';
import '../../../helpers/localized_app.dart';

/// L'écran se referme en rendant son issue : il lui faut donc une route à
/// dépiler. Ce harnais l'ouvre depuis un écran d'accueil et retient l'issue.
class GateHost extends StatefulWidget {
  const GateHost({required this.service, required this.permission, super.key});

  final FakePermissionService service;
  final AppPermission permission;

  @override
  State<GateHost> createState() => GateHostState();
}

class GateHostState extends State<GateHost> {
  PermissionOutcome? outcome;
  bool closed = false;

  Future<void> _open() async {
    final result = await Navigator.of(context).push<PermissionOutcome>(
      MaterialPageRoute<PermissionOutcome>(
        builder: (_) => PermissionGateView(
          viewModel: PermissionGateViewModel(
            service: widget.service,
            permission: widget.permission,
          ),
        ),
      ),
    );
    setState(() {
      outcome = result;
      closed = true;
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: ElevatedButton(
        onPressed: () => unawaited(_open()),
        child: const Text('ouvrir'),
      ),
    ),
  );
}

Future<GateHostState> openGate(
  WidgetTester tester,
  FakePermissionService service, {
  AppPermission permission = AppPermission.microphone,
}) async {
  await pumpLocalized(
    tester,
    GateHost(service: service, permission: permission),
  );
  // Relevé avant l'ouverture : une fois la porte poussée, l'écran d'accueil
  // passe hors-scène et `find.byType` ne le voit plus.
  final host = tester.state<GateHostState>(find.byType(GateHost));
  await tester.tap(find.text('ouvrir'));
  await tester.pumpAndSettle();
  return host;
}

void main() {
  setUpAll(initLocalization);

  testWidgets('le micro s’explique avant d’être demandé', (tester) async {
    await openGate(tester, FakePermissionService());

    expect(find.text('NotAlone a besoin du micro'), findsOneWidget);
    expect(
      find.textContaining("L'audio ne quitte jamais ton téléphone"),
      findsOneWidget,
    );
    expect(find.widgetWithText(FilledButton, 'Autoriser'), findsOneWidget);
    expect(
      find.text('Ouvrir les réglages'),
      findsNothing,
      reason: 'rien à débloquer tant que rien n’a été refusé',
    );
  });

  testWidgets('permission accordée → l’écran se referme et laisse passer', (
    tester,
  ) async {
    final host = await openGate(
      tester,
      FakePermissionService(afterRequest: AppPermissionStatus.granted),
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Autoriser'));
    await tester.pumpAndSettle();

    expect(host.outcome, PermissionOutcome.granted);
  });

  testWidgets('refus → explication, lien réglages, et pas de crash', (
    tester,
  ) async {
    final service = FakePermissionService(
      afterRequest: AppPermissionStatus.denied,
    );
    await openGate(tester, service);

    await tester.tap(find.widgetWithText(FilledButton, 'Autoriser'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('ce que tu dis ne sera pas transcrit'),
      findsOneWidget,
    );
    expect(find.text('Réessayer'), findsOneWidget);

    await tester.tap(find.text('Ouvrir les réglages'));
    await tester.pumpAndSettle();

    expect(service.settingsCount, 1);
  });

  testWidgets('refus du micro → l’hôte peut continuer sans capter sa voix', (
    tester,
  ) async {
    final host = await openGate(
      tester,
      FakePermissionService(afterRequest: AppPermissionStatus.denied),
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Autoriser'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continuer sans mon micro'));
    await tester.pumpAndSettle();

    expect(host.outcome, PermissionOutcome.skipped);
  });

  testWidgets('refus définitif → plus de « Réessayer », seuls les réglages', (
    tester,
  ) async {
    await openGate(
      tester,
      FakePermissionService(
        afterRequest: AppPermissionStatus.permanentlyDenied,
      ),
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Autoriser'));
    await tester.pumpAndSettle();

    expect(find.text('Réessayer'), findsNothing);
    expect(find.text('Ouvrir les réglages'), findsOneWidget);
  });

  testWidgets('caméra refusée → repli « Chercher sur le réseau »', (
    tester,
  ) async {
    final host = await openGate(
      tester,
      FakePermissionService(afterRequest: AppPermissionStatus.denied),
      permission: AppPermission.camera,
    );
    expect(find.text("NotAlone a besoin de l'appareil photo"), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Autoriser'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chercher sur le réseau'));
    await tester.pumpAndSettle();

    expect(host.outcome, PermissionOutcome.skipped);
  });

  testWidgets('retour arrière → on ne va nulle part', (tester) async {
    final host = await openGate(tester, FakePermissionService());

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(host.closed, isTrue);
    expect(
      host.outcome,
      isNull,
      reason:
          'la porte traduit ce vide en « annulé » : l’appelant n’ouvre rien',
    );
  });
}
