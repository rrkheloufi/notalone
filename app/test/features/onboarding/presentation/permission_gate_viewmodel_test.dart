import 'package:flutter_test/flutter_test.dart';
import 'package:notalone/features/onboarding/domain/onboarding_failure.dart';
import 'package:notalone/features/onboarding/domain/permission_service.dart';
import 'package:notalone/features/onboarding/presentation/permission_gate_viewmodel.dart';

import '../../../helpers/fake_permission_service.dart';

PermissionGateViewModel buildViewModel(FakePermissionService service) =>
    PermissionGateViewModel(
      service: service,
      permission: AppPermission.microphone,
    );

void main() {
  test('avant toute demande, l’écran n’affiche pas de refus', () {
    final viewModel = buildViewModel(FakePermissionService());

    expect(viewModel.status, isNull);
    expect(viewModel.isRefused, isFalse);
    expect(viewModel.canRequestAgain, isTrue);
  });

  test('permission accordée', () async {
    final service = FakePermissionService(
      afterRequest: AppPermissionStatus.granted,
    );
    final viewModel = buildViewModel(service);

    await viewModel.requestCommand.execute();

    expect(service.requestCount, 1);
    expect(viewModel.isGranted, isTrue);
    expect(viewModel.isRefused, isFalse);
  });

  test('refus simple : on peut redemander', () async {
    final viewModel = buildViewModel(
      FakePermissionService(afterRequest: AppPermissionStatus.denied),
    );

    await viewModel.requestCommand.execute();

    expect(viewModel.isRefused, isTrue);
    expect(viewModel.canRequestAgain, isTrue);
  });

  test(
    'refus définitif : seuls les réglages système peuvent débloquer',
    () async {
      final viewModel = buildViewModel(
        FakePermissionService(
          afterRequest: AppPermissionStatus.permanentlyDenied,
        ),
      );

      await viewModel.requestCommand.execute();

      expect(viewModel.isRefused, isTrue);
      expect(viewModel.canRequestAgain, isFalse);
    },
  );

  test(
    'service injoignable : aucune permission n’est supposée accordée',
    () async {
      final service = FakePermissionService()
        ..requestFailure = const PermissionUnavailableFailure('canal absent');
      final viewModel = buildViewModel(service);

      await viewModel.requestCommand.execute();

      expect(viewModel.isGranted, isFalse);
      expect(viewModel.isRefused, isTrue);
      expect(viewModel.requestCommand.error, isTrue);
    },
  );

  test('l’ouverture des réglages est déléguée au service', () async {
    final service = FakePermissionService();
    final viewModel = buildViewModel(service);

    await viewModel.openSettingsCommand.execute();

    expect(service.settingsCount, 1);
  });

  test('la permission demandée est celle passée au ViewModel', () {
    final viewModel = PermissionGateViewModel(
      service: FakePermissionService(),
      permission: AppPermission.camera,
    );

    expect(viewModel.permission, AppPermission.camera);
  });
}
