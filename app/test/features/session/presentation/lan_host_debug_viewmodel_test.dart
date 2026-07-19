import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:notalone/core/result/result.dart';
import 'package:notalone/features/session/domain/lan_server.dart';
import 'package:notalone/features/session/domain/qr_session_payload.dart';
import 'package:notalone/features/session/domain/session_failure.dart';
import 'package:notalone/features/session/presentation/lan_host_debug_viewmodel.dart';

final class _FakeServer implements LanServer {
  final StreamController<LanServerEvent> _events = StreamController.broadcast();
  final List<String> broadcasts = [];
  Result<LanServerInfo>? nextStartResult;
  int stopCalls = 0;

  @override
  Stream<LanServerEvent> get events => _events.stream;

  @override
  Future<Result<LanServerInfo>> start() async =>
      nextStartResult ??
      const Result.ok(
        LanServerInfo(host: '192.168.1.10', port: 40000, token: 'tok'),
      );

  @override
  void broadcast(String text) => broadcasts.add(text);

  @override
  Future<void> stop() async => stopCalls++;

  void emit(LanServerEvent event) => _events.add(event);
}

void main() {
  test('start → QR encodant la session, adresse exposée', () async {
    final server = _FakeServer();
    final viewModel = LanHostDebugViewModel(
      server: server,
      sessionName: 'Repas',
    );

    await viewModel.startCommand.execute();

    expect(viewModel.isRunning, isTrue);
    final payload = QrSessionPayload.decode(viewModel.qrData!).valueOrNull;
    expect(
      payload,
      const QrSessionPayload(
        sessionName: 'Repas',
        host: '192.168.1.10',
        port: 40000,
        token: 'tok',
      ),
    );
    expect(viewModel.host, '192.168.1.10');
    expect(viewModel.port, 40000);
  });

  test('échec de démarrage → failure exposée, pas démarré', () async {
    final server = _FakeServer()
      ..nextStartResult = const Result.err(ServerStartFailure('pas de WiFi'));
    final viewModel = LanHostDebugViewModel(server: server);

    await viewModel.startCommand.execute();

    expect(viewModel.startCommand.error, isTrue);
    expect(viewModel.isRunning, isFalse);
  });

  test('événements serveur → journal typé', () async {
    final server = _FakeServer();
    final viewModel = LanHostDebugViewModel(server: server);
    await viewModel.startCommand.execute();

    server
      ..emit(const LanClientConnected(clientId: 1))
      ..emit(const LanMessageReceived(clientId: 1, text: 'salut'))
      ..emit(const LanClientDisconnected(clientId: 1));
    await pumpEventQueue();

    expect(viewModel.log, hasLength(3));
    expect(viewModel.log[0], isA<GuestJoinedEntry>());
    expect((viewModel.log[1] as GuestMessageEntry).text, 'salut');
    expect(viewModel.log[2], isA<GuestLeftEntry>());
  });

  test('send → broadcast + journal ; stop → serveur arrêté', () async {
    final server = _FakeServer();
    final viewModel = LanHostDebugViewModel(server: server);
    await viewModel.startCommand.execute();

    await viewModel.sendCommand.execute('bonjour');
    expect(server.broadcasts, ['bonjour']);
    expect(viewModel.log.single, isA<HostMessageEntry>());

    await viewModel.stopCommand.execute();
    expect(viewModel.isRunning, isFalse);
    expect(server.stopCalls, 1);
  });
}
