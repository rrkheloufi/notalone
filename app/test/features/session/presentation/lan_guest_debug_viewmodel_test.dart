import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:notalone/core/result/result.dart';
import 'package:notalone/features/session/domain/lan_client.dart';
import 'package:notalone/features/session/domain/qr_session_payload.dart';
import 'package:notalone/features/session/domain/session_failure.dart';
import 'package:notalone/features/session/presentation/lan_guest_debug_viewmodel.dart';

const validPayload = QrSessionPayload(
  sessionName: 'Repas',
  host: '192.168.1.10',
  port: 40000,
  token: 'tok',
);

final class _FakeClient implements LanClient {
  final StreamController<String> _messages = StreamController.broadcast();
  final StreamController<void> _disconnections = StreamController.broadcast();
  final List<String> sent = [];
  QrSessionPayload? connectedTo;
  Result<void> connectResult = const Result.ok(null);
  List<Duration> pingResults = const [
    Duration(milliseconds: 50),
    Duration(milliseconds: 10),
    Duration(milliseconds: 30),
    Duration(milliseconds: 40),
    Duration(milliseconds: 20),
  ];
  int _pingIndex = 0;
  int disconnectCalls = 0;

  @override
  Future<Result<void>> connect(QrSessionPayload payload) async {
    if (connectResult.isOk) connectedTo = payload;
    return connectResult;
  }

  @override
  Stream<String> get messages => _messages.stream;

  @override
  Stream<void> get disconnections => _disconnections.stream;

  @override
  void send(String text) => sent.add(text);

  @override
  Future<Result<Duration>> ping() async =>
      Result.ok(pingResults[_pingIndex++ % pingResults.length]);

  @override
  Future<void> disconnect() async => disconnectCalls++;

  void receive(String text) => _messages.add(text);

  void dropConnection() => _disconnections.add(null);
}

void main() {
  test('scan valide → connecté au payload décodé, RTT médian mesuré', () async {
    final client = _FakeClient();
    final viewModel = LanGuestDebugViewModel(client: client);

    await viewModel.scanCommand.execute(validPayload.encode());
    await pumpEventQueue();

    expect(viewModel.state, GuestConnectionState.connected);
    expect(client.connectedTo, validPayload);
    // 5 pings [50,10,30,40,20] → médiane 30 ms.
    expect(viewModel.medianRtt, const Duration(milliseconds: 30));
  });

  test('QR illisible → failure exposée, on reste en scan', () async {
    final client = _FakeClient();
    final viewModel = LanGuestDebugViewModel(client: client);

    await viewModel.scanCommand.execute('pas un payload');

    expect(
      viewModel.scanCommand.result?.failureOrNull,
      isA<QrPayloadMalformedFailure>(),
    );
    expect(viewModel.state, GuestConnectionState.scanning);
    expect(client.connectedTo, isNull);
  });

  test(
    'timeout de connexion (R7) → failure dédiée, on reste en scan',
    () async {
      final client = _FakeClient()
        ..connectResult = const Result.err(ConnectionTimeoutFailure());
      final viewModel = LanGuestDebugViewModel(client: client);

      await viewModel.scanCommand.execute(validPayload.encode());

      expect(
        viewModel.scanCommand.result?.failureOrNull,
        isA<ConnectionTimeoutFailure>(),
      );
      expect(viewModel.state, GuestConnectionState.scanning);
    },
  );

  test('messages reçus et envoyés dans le fil', () async {
    final client = _FakeClient();
    final viewModel = LanGuestDebugViewModel(client: client);
    await viewModel.scanCommand.execute(validPayload.encode());

    client.receive('coucou');
    await pumpEventQueue();
    await viewModel.sendCommand.execute('réponse');

    expect(viewModel.messages, [
      (own: false, text: 'coucou'),
      (own: true, text: 'réponse'),
    ]);
    expect(client.sent, ['réponse']);
  });

  test('connexion perdue → état déconnecté, rescan possible', () async {
    final client = _FakeClient();
    final viewModel = LanGuestDebugViewModel(client: client);
    await viewModel.scanCommand.execute(validPayload.encode());

    client.dropConnection();
    await pumpEventQueue();
    expect(viewModel.state, GuestConnectionState.disconnected);

    viewModel.resetToScan();
    expect(viewModel.state, GuestConnectionState.scanning);
    expect(viewModel.messages, isEmpty);
    expect(viewModel.medianRtt, isNull);
  });
}
