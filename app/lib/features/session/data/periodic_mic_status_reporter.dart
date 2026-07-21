import 'dart:async';

import 'package:notalone/features/capture/domain/battery_level_source.dart';
import 'package:notalone/features/capture/domain/capture_status.dart';
import 'package:notalone/features/capture/domain/mic_status_reporter.dart';
import 'package:notalone/features/session/domain/protocol/session_message.dart';
import 'package:notalone/features/session/domain/supervision_config.dart';

/// Fabrique de minuteur périodique, injectée pour que les tests pilotent le
/// temps (même intention que le `TimerFactory` de la fusion, MVP-09).
typedef PeriodicTimerFactory =
    Timer Function(Duration period, void Function(Timer) callback);

/// Publication d'un état de micro, quel qu'en soit le destinataire.
typedef MicStatusSink = void Function(MicStatusState state, int? batteryPct);

/// Traduit l'état de capture de ce téléphone en `mic_status` et le pousse vers
/// [MicStatusSink] (cf. cowork/02-architecture.md §4, doc 03 R5).
///
/// **Une seule classe pour les deux rôles** : l'invité et l'hôte ont exactement
/// la même chose à dire, seul le destinataire change. C'est
/// `app_dependencies.dart` qui branche le socket (invité) ou le use case de
/// supervision (hôte, qui n'a pas de socket vers lui-même) — la DI est
/// précisément l'endroit où cette différence appartient.
///
/// Deux déclencheurs :
/// - **le changement d'état**, envoyé immédiatement : c'est lui que vise le
///   critère « coupure du micro visible chez l'hôte < 10 s » ;
/// - **une réémission périodique**, pour la batterie seule, qui ne bouge pas à
///   cette échelle. Elle rattrape aussi un message perdu pendant une coupure.
class PeriodicMicStatusReporter implements MicStatusReporter {
  PeriodicMicStatusReporter({
    required this._publish,
    required this._battery,
    SupervisionConfig config = const SupervisionConfig(),
    PeriodicTimerFactory scheduleEvery = Timer.periodic,
  }) {
    _refresh = scheduleEvery(
      config.batteryRefreshInterval,
      (_) => unawaited(_send()),
    );
  }

  final MicStatusSink _publish;
  final BatteryLevelSource _battery;

  late final Timer _refresh;

  /// Nul tant que la capture n'a rien annoncé. Le minuteur ne publie donc rien
  /// avant le premier [report] : un invité qui vient d'entrer serait autrement
  /// signalé « micro coupé » avant même d'avoir eu l'occasion de démarrer.
  CaptureStatus? _status;

  bool _disposed = false;

  @override
  void report(CaptureStatus status) {
    if (_disposed || status == _status) return;
    _status = status;
    unawaited(_send());
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _refresh.cancel();
  }

  Future<void> _send() async {
    final status = _status;
    if (_disposed || status == null) return;
    final battery = await _battery.currentLevel();
    // La lecture de batterie est asynchrone : l'état a pu changer, ou le
    // rapporteur être fermé, pendant qu'elle revenait.
    if (_disposed) return;
    _publish(_toWireState(_status ?? status), battery);
  }

  /// `idle` n'existe pas sur le fil : les trois états du protocole décrivent ce
  /// que l'hôte doit comprendre, et une capture arrêtée par l'invité produit
  /// exactement le même symptôme qu'un micro coupé — plus rien n'arrive de lui.
  /// C'est aussi le message que l'hôte peut agir (« le micro de Paul est
  /// coupé »), là où « idle » ne lui dirait rien.
  static MicStatusState _toWireState(CaptureStatus status) => switch (status) {
    CaptureStatus.active => MicStatusState.active,
    CaptureStatus.interrupted => MicStatusState.interrupted,
    CaptureStatus.muted || CaptureStatus.idle => MicStatusState.muted,
  };
}
