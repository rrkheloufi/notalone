import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:notalone/core/l10n/l10n_keys.dart';
import 'package:notalone/features/onboarding/presentation/permission_gate.dart';
import 'package:notalone/features/onboarding/presentation/permission_gate_viewmodel.dart';
import 'package:notalone/features/session/presentation/home_viewmodel.dart';

/// Écrans ouverts depuis la home. Regroupés en paramètre pour que l'accueil
/// reste testable sans construire le vrai graphe de dépendances (serveur
/// WebSocket, caméra, mDNS).
class HomeDestinations {
  const HomeDestinations({
    required this.hostLobby,
    required this.join,
    required this.settings,
    required this.capture,
  });

  final Widget Function(String name) hostLobby;

  /// `withScanner` est faux quand la caméra a été refusée : l'invité choisit
  /// alors sa conversation dans la liste mDNS.
  final Widget Function({required String name, required bool withScanner}) join;

  final Widget Function() settings;

  /// Écran « mon micro » : l'invité vérifie que sa voix est bien captée.
  final Widget Function() capture;
}

/// Accueil : « Nouvelle conversation » ou « Rejoindre », rien d'autre
/// (cf. cowork/01-cadrage-produit.md §3).
class HomeView extends StatefulWidget {
  const HomeView({
    required this.viewModel,
    required this.destinations,
    required this.microphoneGate,
    required this.cameraGate,
    super.key,
  });

  final HomeViewModel viewModel;
  final HomeDestinations destinations;
  final PermissionGate microphoneGate;
  final PermissionGate cameraGate;

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  @override
  void dispose() {
    widget.viewModel.dispose();
    super.dispose();
  }

  Future<void> _push(Widget screen) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => screen));

  Future<void> _startConversation() async {
    final outcome = await widget.microphoneGate(context);
    // Refus non bloquant : l'hôte est le lecteur, il doit pouvoir tenir la
    // conversation même sans capter sa propre voix (décision Rayan, MVP-07).
    if (outcome == PermissionOutcome.cancelled || !mounted) return;
    await _push(widget.destinations.hostLobby(widget.viewModel.name));
  }

  Future<void> _join() async {
    final outcome = await widget.cameraGate(context);
    if (outcome == PermissionOutcome.cancelled || !mounted) return;
    await _push(
      widget.destinations.join(
        name: widget.viewModel.name,
        withScanner: outcome == PermissionOutcome.granted,
      ),
    );
  }

  Future<void> _openSettings() async {
    await _push(widget.destinations.settings());
    // Le prénom a pu changer : la home est la seule à le transmettre ensuite.
    if (mounted) await widget.viewModel.reloadCommand.execute();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(L10nKeys.appTitle.tr()),
        actions: [
          IconButton(
            onPressed: () => unawaited(_openSettings()),
            icon: const Icon(Icons.settings),
            tooltip: L10nKeys.homeSettings.tr(),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ListenableBuilder(
              listenable: widget.viewModel,
              builder: (context, _) => Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    L10nKeys.homeGreeting.tr(
                      namedArgs: {'name': widget.viewModel.name},
                    ),
                    style: Theme.of(context).textTheme.headlineLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  FilledButton.icon(
                    onPressed: () => unawaited(_startConversation()),
                    icon: const Icon(Icons.qr_code_2),
                    label: Text(L10nKeys.homeNewConversation.tr()),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    onPressed: () => unawaited(_join()),
                    icon: const Icon(Icons.qr_code_scanner),
                    label: Text(L10nKeys.homeJoin.tr()),
                  ),
                  const SizedBox(height: 32),
                  OutlinedButton(
                    onPressed: () =>
                        unawaited(_push(widget.destinations.capture())),
                    child: Text(L10nKeys.captureOpen.tr()),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
