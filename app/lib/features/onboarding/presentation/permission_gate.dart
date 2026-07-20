import 'package:flutter/material.dart';
import 'package:notalone/features/onboarding/domain/permission_service.dart';
import 'package:notalone/features/onboarding/presentation/permission_gate_view.dart';
import 'package:notalone/features/onboarding/presentation/permission_gate_viewmodel.dart';

/// Porte à franchir avant d'ouvrir un écran qui a besoin d'une permission.
/// Les vues la reçoivent injectée, ce qui les rend testables sans plateforme.
typedef PermissionGate =
    Future<PermissionOutcome> Function(BuildContext context);

/// Fabrique la porte réelle : elle n'ouvre l'écran d'explication que si la
/// permission n'est pas déjà accordée — au deuxième passage, l'invité ne voit
/// rien et enchaîne directement (< 10 s pour rejoindre, doc 01 §8).
PermissionGate permissionGate({
  required PermissionService service,
  required AppPermission permission,
}) {
  return (BuildContext context) async {
    final current = await service.status(permission);
    if (current.valueOrNull == AppPermissionStatus.granted) {
      return PermissionOutcome.granted;
    }
    if (!context.mounted) return PermissionOutcome.cancelled;
    final outcome = await Navigator.of(context).push<PermissionOutcome>(
      MaterialPageRoute<PermissionOutcome>(
        builder: (_) => PermissionGateView(
          viewModel: PermissionGateViewModel(
            service: service,
            permission: permission,
          ),
        ),
      ),
    );
    // Retour arrière : l'utilisateur n'a rien décidé, on ne va nulle part.
    return outcome ?? PermissionOutcome.cancelled;
  };
}
