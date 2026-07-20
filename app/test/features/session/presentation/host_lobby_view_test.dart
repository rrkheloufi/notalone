import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notalone/core/result/result.dart';
import 'package:notalone/features/session/domain/host_server.dart';
import 'package:notalone/features/session/domain/participant.dart';
import 'package:notalone/features/session/domain/protocol/session_message.dart';
import 'package:notalone/features/session/domain/session_discovery.dart';
import 'package:notalone/features/session/domain/session_failure.dart';
import 'package:notalone/features/session/presentation/host_lobby_view.dart';
import 'package:notalone/features/session/presentation/host_lobby_viewmodel.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';

import '../../../helpers/localized_app.dart';

const host = Participant(
  id: 'h1',
  name: 'Rayan',
  colorIndex: 0,
  isHost: true,
  isConnected: true,
);

const guest = Participant(
  id: 'g1',
  name: 'Camille',
  colorIndex: 1,
  isHost: false,
  isConnected: true,
);

final class _FakeHostServer implements HostServer {
  final StreamController<HostServerEvent> _events =
      StreamController.broadcast();

  Result<HostServerInfo> startResult = const Result.ok(
    HostServerInfo(
      host: '192.168.1.10',
      port: 40000,
      token: 'tok',
      hostParticipant: host,
    ),
  );

  @override
  List<Participant> participants = const [host];

  @override
  Stream<HostServerEvent> get events => _events.stream;

  @override
  Future<Result<HostServerInfo>> start({required String hostName}) async =>
      startResult;

  @override
  void broadcast(SessionMessage message) {}

  @override
  void sendTo(String participantId, SessionMessage message) {}

  @override
  Future<void> endSession() async {}

  void emit(HostServerEvent event) => _events.add(event);
}

final class _FakeAdvertiser implements SessionAdvertiser {
  Result<void> advertiseResult = const Result.ok(null);

  @override
  Future<Result<void>> advertise({
    required String sessionName,
    required int port,
    required String token,
  }) async => advertiseResult;

  @override
  Future<void> stop() async {}
}

({
  HostLobbyViewModel viewModel,
  _FakeHostServer server,
  _FakeAdvertiser advertiser,
})
build() {
  final server = _FakeHostServer();
  final advertiser = _FakeAdvertiser();
  return (
    viewModel: HostLobbyViewModel(
      server: server,
      advertiser: advertiser,
      hostName: 'Rayan',
      sessionName: 'Conversation de Rayan',
    ),
    server: server,
    advertiser: advertiser,
  );
}

void main() {
  setUpAll(initLocalization);

  testWidgets('la session démarre seule et affiche son QR', (tester) async {
    final (:viewModel, :server, advertiser: _) = build();

    await pumpLocalized(tester, HostLobbyView(viewModel: viewModel));

    expect(find.byType(PrettyQrView), findsOneWidget);
    expect(find.text('Fais scanner ce code aux autres'), findsOneWidget);
    expect(find.text('Rayan'), findsOneWidget);
  });

  testWidgets('les convives apparaissent avec leur état', (tester) async {
    final (:viewModel, :server, advertiser: _) = build();
    await pumpLocalized(tester, HostLobbyView(viewModel: viewModel));

    server
      ..participants = const [host, guest]
      ..emit(
        const ParticipantJoined(participant: guest, isReconnection: false),
      );
    await tester.pumpAndSettle();

    expect(find.text('Camille'), findsOneWidget);
    expect(find.text('connecté'), findsOneWidget);
    expect(find.text('toi'), findsOneWidget);
    expect(find.text('Autour de la table (2)'), findsOneWidget);
  });

  testWidgets('un invité déconnecté est signalé', (tester) async {
    final (:viewModel, :server, advertiser: _) = build();
    await pumpLocalized(tester, HostLobbyView(viewModel: viewModel));

    const gone = Participant(
      id: 'g1',
      name: 'Camille',
      colorIndex: 1,
      isHost: false,
      isConnected: false,
    );
    server
      ..participants = const [host, gone]
      ..emit(const ParticipantDisconnected(gone));
    await tester.pumpAndSettle();

    expect(find.text('déconnecté'), findsOneWidget);
    expect(find.byIcon(Icons.signal_wifi_off), findsOneWidget);
  });

  testWidgets('un refus est montré à l’hôte, puis effaçable', (tester) async {
    final (:viewModel, :server, advertiser: _) = build();
    await pumpLocalized(tester, HostLobbyView(viewModel: viewModel));

    server.emit(
      const ParticipantRejected(reason: 'Session complète', closeCode: 4002),
    );
    await tester.pumpAndSettle();
    expect(find.text('Session complète'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.text('Session complète'), findsNothing);
  });

  testWidgets('la mention du secours mDNS disparaît si l’annonce échoue', (
    tester,
  ) async {
    final (:viewModel, server: _, :advertiser) = build();
    advertiser.advertiseResult = const Result.err(
      DiscoveryUnavailableFailure('service absent'),
    );

    await pumpLocalized(tester, HostLobbyView(viewModel: viewModel));

    expect(find.byType(PrettyQrView), findsOneWidget);
    expect(
      find.textContaining('visible sur le réseau'),
      findsNothing,
      reason: 'ne rien promettre que le réseau ne tienne',
    );
  });

  testWidgets('WiFi coupé → message d’erreur et bouton de reprise', (
    tester,
  ) async {
    final (:viewModel, :server, advertiser: _) = build();
    server.startResult = const Result.err(
      ServerStartFailure('aucune adresse IPv4 locale (WiFi coupé ?)'),
    );

    await pumpLocalized(tester, HostLobbyView(viewModel: viewModel));

    expect(find.textContaining('WiFi coupé'), findsOneWidget);
    expect(find.text('Réessayer'), findsOneWidget);
    expect(find.byType(PrettyQrView), findsNothing);
  });
}
