import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notalone/features/onboarding/presentation/permission_gate.dart';
import 'package:notalone/features/onboarding/presentation/permission_gate_viewmodel.dart';
import 'package:notalone/features/session/presentation/home_view.dart';
import 'package:notalone/features/session/presentation/home_viewmodel.dart';

import '../../../helpers/fake_user_profile_repository.dart';
import '../../../helpers/localized_app.dart';

/// Porte factice : rend l'issue voulue sans jamais toucher à la plateforme.
PermissionGate gateReturning(PermissionOutcome outcome) =>
    (context) async => outcome;

/// Écran d'arrivée reconnaissable, à la place du vrai (serveur WebSocket,
/// caméra, mDNS — hors de portée d'un widget test). Sa barre porte le bouton
/// retour dont les tests ont besoin pour revenir à la home.
Widget stub(String label) => Scaffold(
  appBar: AppBar(title: Text('écran $label')),
  body: const SizedBox.shrink(),
);

({Widget view, List<String> opened}) buildView({
  PermissionOutcome microphone = PermissionOutcome.granted,
  PermissionOutcome camera = PermissionOutcome.granted,
  FakeUserProfileRepository? profiles,
  Widget Function()? settings,
}) {
  final opened = <String>[];
  return (
    view: HomeView(
      viewModel: HomeViewModel(
        profiles: profiles ?? FakeUserProfileRepository(name: 'Camille'),
        name: 'Camille',
      ),
      microphoneGate: gateReturning(microphone),
      cameraGate: gateReturning(camera),
      destinations: HomeDestinations(
        hostLobby: (name) {
          opened.add('hôte:$name');
          return stub('hôte');
        },
        join: ({required name, required withScanner}) {
          opened.add('invité:$name:scanner=$withScanner');
          return stub('invité');
        },
        settings: settings ??
            () {
              opened.add('réglages');
              return stub('réglages');
            },
        vadDebug: () => stub('vad'),
      ),
    ),
    opened: opened,
  );
}

void main() {
  setUpAll(initLocalization);

  testWidgets('la home salue par le prénom et propose les deux chemins', (
    tester,
  ) async {
    final (:view, opened: _) = buildView();
    await pumpLocalized(tester, view);

    expect(find.text('Bonjour Camille'), findsOneWidget);
    expect(find.text('Nouvelle conversation'), findsOneWidget);
    expect(find.text('Rejoindre'), findsOneWidget);
  });

  testWidgets('micro accordé → le salon hôte s’ouvre avec le prénom', (
    tester,
  ) async {
    final (:view, :opened) = buildView();
    await pumpLocalized(tester, view);

    await tester.tap(find.text('Nouvelle conversation'));
    await tester.pumpAndSettle();

    expect(opened, ['hôte:Camille']);
  });

  testWidgets('micro refusé → l’hôte entre quand même (il est le lecteur)', (
    tester,
  ) async {
    final (:view, :opened) = buildView(microphone: PermissionOutcome.skipped);
    await pumpLocalized(tester, view);

    await tester.tap(find.text('Nouvelle conversation'));
    await tester.pumpAndSettle();

    expect(opened, ['hôte:Camille']);
  });

  testWidgets('porte annulée → aucun écran ne s’ouvre', (tester) async {
    final (:view, :opened) = buildView(microphone: PermissionOutcome.cancelled);
    await pumpLocalized(tester, view);

    await tester.tap(find.text('Nouvelle conversation'));
    await tester.pumpAndSettle();

    expect(opened, isEmpty);
    expect(find.text('Bonjour Camille'), findsOneWidget);
  });

  testWidgets('caméra accordée → parcours invité avec scanner', (tester) async {
    final (:view, :opened) = buildView();
    await pumpLocalized(tester, view);

    await tester.tap(find.text('Rejoindre'));
    await tester.pumpAndSettle();

    expect(opened, ['invité:Camille:scanner=true']);
  });

  testWidgets('caméra refusée → parcours invité rabattu sur le réseau', (
    tester,
  ) async {
    final (:view, :opened) = buildView(camera: PermissionOutcome.skipped);
    await pumpLocalized(tester, view);

    await tester.tap(find.text('Rejoindre'));
    await tester.pumpAndSettle();

    expect(opened, ['invité:Camille:scanner=false']);
  });

  testWidgets('prénom changé dans les réglages → la home se met à jour', (
    tester,
  ) async {
    final profiles = FakeUserProfileRepository(name: 'Camille');
    final (:view, opened: _) = buildView(
      profiles: profiles,
      settings: () {
        // L'écran de réglages réel est testé à part ; ici seul compte le fait
        // que la home relise le prénom en revenant.
        profiles.name = 'Paul';
        return stub('réglages');
      },
    );
    await pumpLocalized(tester, view);

    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.text('Bonjour Paul'), findsOneWidget);
  });
}
