import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notalone/features/onboarding/domain/permission_service.dart';
import 'package:notalone/features/onboarding/presentation/permission_gate.dart';
import 'package:notalone/features/onboarding/presentation/permission_gate_viewmodel.dart';

import '../../../helpers/fake_permission_service.dart';
import '../../../helpers/localized_app.dart';

/// Écran qui franchit la porte au tap, comme le fait la home.
class GateCaller extends StatefulWidget {
  const GateCaller({required this.gate, super.key});

  final PermissionGate gate;

  @override
  State<GateCaller> createState() => GateCallerState();
}

class GateCallerState extends State<GateCaller> {
  PermissionOutcome? outcome;

  Future<void> _cross() async {
    final result = await widget.gate(context);
    setState(() => outcome = result);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: ElevatedButton(
        onPressed: () => unawaited(_cross()),
        child: const Text('franchir'),
      ),
    ),
  );
}

Future<GateCallerState> tapGate(
  WidgetTester tester,
  FakePermissionService service,
) async {
  await pumpLocalized(
    tester,
    GateCaller(
      gate: permissionGate(
        service: service,
        permission: AppPermission.microphone,
      ),
    ),
  );
  final caller = tester.state<GateCallerState>(find.byType(GateCaller));
  await tester.tap(find.text('franchir'));
  await tester.pumpAndSettle();
  return caller;
}

void main() {
  setUpAll(initLocalization);

  testWidgets('permission déjà accordée → aucun écran, on enchaîne', (
    tester,
  ) async {
    final service = FakePermissionService(
      current: AppPermissionStatus.granted,
    );

    final caller = await tapGate(tester, service);

    expect(caller.outcome, PermissionOutcome.granted);
    expect(
      find.text('NotAlone a besoin du micro'),
      findsNothing,
      reason: 'redemander à chaque fois coûterait les 10 s du doc 01 §8',
    );
    expect(service.requestCount, 0);
  });

  testWidgets('permission pas encore accordée → l’écran s’explique', (
    tester,
  ) async {
    final service = FakePermissionService(
      afterRequest: AppPermissionStatus.granted,
    );

    final caller = await tapGate(tester, service);
    expect(find.text('NotAlone a besoin du micro'), findsOneWidget);
    expect(caller.outcome, isNull, reason: 'rien de décidé tant qu’on y est');

    await tester.tap(find.widgetWithText(FilledButton, 'Autoriser'));
    await tester.pumpAndSettle();

    expect(caller.outcome, PermissionOutcome.granted);
  });

  testWidgets('retour arrière sur l’écran → annulé', (tester) async {
    final caller = await tapGate(tester, FakePermissionService());

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(caller.outcome, PermissionOutcome.cancelled);
  });
}
