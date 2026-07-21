import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:notalone/features/capture/domain/battery_level_source.dart';
import 'package:notalone/features/capture/domain/capture_status.dart';
import 'package:notalone/features/session/data/periodic_mic_status_reporter.dart';
import 'package:notalone/features/session/domain/protocol/session_message.dart';
import 'package:notalone/features/session/domain/supervision_config.dart';

class _FakeBattery implements BatteryLevelSource {
  int? level = 80;
  int reads = 0;

  @override
  Future<int?> currentLevel() async {
    reads++;
    return level;
  }
}

/// Minuteur périodique piloté par le test : `tick()` déclenche ce que le vrai
/// `Timer.periodic` ferait au bout de l'intervalle, sans attendre.
class _ManualPeriodicTimer implements Timer {
  _ManualPeriodicTimer(this._callback);

  final void Function(Timer) _callback;
  bool cancelled = false;

  void fire() => _callback(this);

  @override
  void cancel() => cancelled = true;

  @override
  bool get isActive => !cancelled;

  @override
  int get tick => 0;
}

({
  PeriodicMicStatusReporter reporter,
  List<({MicStatusState state, int? batteryPct})> sent,
  _FakeBattery battery,
  _ManualPeriodicTimer timer,
})
build({SupervisionConfig config = const SupervisionConfig()}) {
  final sent = <({MicStatusState state, int? batteryPct})>[];
  final battery = _FakeBattery();
  late _ManualPeriodicTimer timer;
  final reporter = PeriodicMicStatusReporter(
    battery: battery,
    config: config,
    publish: (state, batteryPct) =>
        sent.add((state: state, batteryPct: batteryPct)),
    scheduleEvery: (_, callback) => timer = _ManualPeriodicTimer(callback),
  );
  return (reporter: reporter, sent: sent, battery: battery, timer: timer);
}

void main() {
  test('chaque état de capture a sa traduction sur le fil', () async {
    final (:reporter, :sent, battery: _, timer: _) = build();
    addTearDown(reporter.dispose);

    for (final (status, expected) in const [
      (CaptureStatus.active, MicStatusState.active),
      (CaptureStatus.interrupted, MicStatusState.interrupted),
      (CaptureStatus.muted, MicStatusState.muted),
      // `idle` n'existe pas dans le protocole : une capture arrêtée par
      // l'invité produit le même symptôme qu'un micro coupé, et c'est le
      // message que l'hôte peut agir.
      (CaptureStatus.idle, MicStatusState.muted),
    ]) {
      sent.clear();
      reporter.report(status);
      await pumpEventQueue();
      expect(sent.single.state, expected, reason: status.name);
    }
  });

  test('un changement d’état part immédiatement', () async {
    // Le critère « coupure du micro visible chez l'hôte < 10 s » tient parce
    // que l'état est poussé, pas attendu au prochain tour de minuteur.
    final (:reporter, :sent, battery: _, :timer) = build();
    addTearDown(reporter.dispose);

    reporter.report(CaptureStatus.active);
    await pumpEventQueue();

    expect(sent, hasLength(1));
    expect(timer.isActive, isTrue, reason: 'sans avoir eu à attendre un tick');
  });

  test('rien ne part avant le premier état connu', () async {
    // Un invité qui vient d'entrer serait autrement signalé « micro coupé »
    // avant même d'avoir eu l'occasion de démarrer sa capture.
    final (reporter: _, :sent, battery: _, :timer) = build();

    timer.fire();
    await pumpEventQueue();

    expect(sent, isEmpty);
  });

  test('le même état répété ne repart pas', () async {
    final (:reporter, :sent, battery: _, timer: _) = build();
    addTearDown(reporter.dispose);

    reporter
      ..report(CaptureStatus.active)
      ..report(CaptureStatus.active);
    await pumpEventQueue();

    expect(sent, hasLength(1));
  });

  test('le minuteur réémet l’état courant avec la batterie du moment',
      () async {
    final (:reporter, :sent, :battery, :timer) = build();
    addTearDown(reporter.dispose);
    reporter.report(CaptureStatus.active);
    await pumpEventQueue();

    battery.level = 15;
    timer.fire();
    await pumpEventQueue();

    expect(sent, hasLength(2));
    expect(sent.last.state, MicStatusState.active);
    expect(sent.last.batteryPct, 15);
  });

  test('batterie illisible → l’état du micro part quand même', () async {
    // C'est l'information la plus utile des deux : la taire parce que la
    // batterie manque priverait l'hôte de la seule chose qu'il peut traiter.
    final (:reporter, :sent, :battery, timer: _) = build();
    addTearDown(reporter.dispose);
    battery.level = null;

    reporter.report(CaptureStatus.muted);
    await pumpEventQueue();

    expect(sent.single.state, MicStatusState.muted);
    expect(sent.single.batteryPct, isNull);
  });

  test('la période de réémission vient de la config', () {
    final periods = <Duration>[];
    final reporter = PeriodicMicStatusReporter(
      battery: _FakeBattery(),
      config: const SupervisionConfig(
        batteryRefreshInterval: Duration(minutes: 2),
      ),
      publish: (_, _) {},
      scheduleEvery: (period, callback) {
        periods.add(period);
        return _ManualPeriodicTimer(callback);
      },
    );
    addTearDown(reporter.dispose);

    expect(periods, [const Duration(minutes: 2)]);
  });

  test('fermé : le minuteur s’arrête et plus rien ne part', () async {
    final (:reporter, :sent, battery: _, :timer) = build();
    reporter.report(CaptureStatus.active);
    await pumpEventQueue();
    sent.clear();

    await reporter.dispose();
    reporter.report(CaptureStatus.muted);
    timer.fire();
    await pumpEventQueue();

    expect(timer.cancelled, isTrue);
    expect(sent, isEmpty);
  });
}
