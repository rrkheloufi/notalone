import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:notalone/core/l10n/l10n_keys.dart';
import 'package:notalone/core/result/failure.dart';
import 'package:notalone/features/capture/domain/capture_failure.dart';
import 'package:notalone/features/capture/domain/capture_status.dart';
import 'package:notalone/features/capture/domain/stt_failure.dart';
import 'package:notalone/features/capture/presentation/capture_viewmodel.dart';

/// Écran de capture de l'invité : ce que son micro entend. Le transcript
/// fusionné, lui, s'affiche chez l'hôte (MVP-12).
class CaptureView extends StatefulWidget {
  const CaptureView({
    required this.viewModel,
    this.ownsViewModel = true,
    super.key,
  });

  final CaptureViewModel viewModel;

  /// Faux quand l'écran est ouvert **depuis une session** : la capture y
  /// appartient au `JoinViewModel` et lui survit — la refermer ne doit pas
  /// couper le micro d'un invité qui range son téléphone dans sa poche
  /// (MVP-13). Vrai pour l'écran « mon micro » de l'accueil, qui construit sa
  /// propre capture et n'a personne d'autre à qui la confier.
  final bool ownsViewModel;

  @override
  State<CaptureView> createState() => _CaptureViewState();
}

class _CaptureViewState extends State<CaptureView> {
  @override
  void dispose() {
    if (widget.ownsViewModel) widget.viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = widget.viewModel;
    return Scaffold(
      appBar: AppBar(title: Text(L10nKeys.captureTitle.tr())),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([
            viewModel,
            viewModel.startCommand,
            viewModel.stopCommand,
            viewModel.toggleMuteCommand,
          ]),
          builder: (context, _) {
            final failure =
                viewModel.startCommand.result?.failureOrNull ??
                viewModel.streamFailure;
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (failure != null) _FailureBanner(failure: failure),
                  if (viewModel.sttFailure case final sttFailure?)
                    _FailureBanner(failure: sttFailure),
                  _StatusRow(viewModel: viewModel),
                  const SizedBox(height: 16),
                  _Controls(viewModel: viewModel),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          L10nKeys.captureSegmentsTitle.tr(),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      if (viewModel.isCapturing)
                        Text(
                          L10nKeys.captureEngine.tr(
                            namedArgs: {'engine': viewModel.engine},
                          ),
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(child: _SegmentList(viewModel: viewModel)),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _FailureBanner extends StatelessWidget {
  const _FailureBanner({required this.failure});

  final Failure failure;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Les pannes qui appellent un geste de l'invité méritent une consigne, pas
    // le message technique de la Failure.
    final message = switch (failure) {
      MicPermissionFailure() => L10nKeys.captureMicPermissionError.tr(),
      SttModelMissingFailure() => L10nKeys.captureSttModelMissing.tr(),
      SttPermissionFailure() => L10nKeys.captureSttPermissionError.tr(),
      SttUnavailableFailure() => L10nKeys.captureSttUnavailable.tr(),
      SttAudioSourceUnsupportedFailure() =>
        L10nKeys.captureSttAudioSourceUnsupported.tr(),
      _ => failure.message,
    };
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(message, style: TextStyle(color: scheme.onErrorContainer)),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.viewModel});

  final CaptureViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, label, color) = switch (viewModel.status) {
      CaptureStatus.idle => (
        Icons.mic_off,
        L10nKeys.captureStatusIdle.tr(),
        scheme.outline,
      ),
      CaptureStatus.active => (
        Icons.mic,
        L10nKeys.captureStatusActive.tr(),
        scheme.primary,
      ),
      CaptureStatus.interrupted => (
        Icons.phone_paused,
        L10nKeys.captureStatusInterrupted.tr(),
        scheme.error,
      ),
      CaptureStatus.muted => (
        Icons.mic_off,
        L10nKeys.captureStatusMuted.tr(),
        scheme.outline,
      ),
    };
    return Row(
      children: [
        Icon(icon, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.titleMedium),
        ),
        if (viewModel.isSpeaking)
          Chip(
            avatar: Icon(Icons.graphic_eq, size: 18, color: scheme.primary),
            label: Text(L10nKeys.captureSpeaking.tr()),
          ),
      ],
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({required this.viewModel});

  final CaptureViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final busy =
        viewModel.startCommand.running ||
        viewModel.stopCommand.running ||
        viewModel.toggleMuteCommand.running;
    if (!viewModel.isCapturing) {
      return FilledButton.icon(
        onPressed: busy
            ? null
            : () => unawaited(viewModel.startCommand.execute()),
        icon: const Icon(Icons.mic),
        label: Text(L10nKeys.captureStart.tr()),
      );
    }
    final muted = viewModel.status == CaptureStatus.muted;
    return Row(
      children: [
        Expanded(
          child: FilledButton.tonalIcon(
            onPressed: busy
                ? null
                : () => unawaited(viewModel.toggleMuteCommand.execute()),
            icon: Icon(muted ? Icons.mic : Icons.mic_off),
            label: Text(
              muted ? L10nKeys.captureUnmute.tr() : L10nKeys.captureMute.tr(),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton.icon(
            onPressed: busy
                ? null
                : () => unawaited(viewModel.stopCommand.execute()),
            icon: const Icon(Icons.stop),
            label: Text(L10nKeys.captureStop.tr()),
          ),
        ),
      ],
    );
  }
}

class _SegmentList extends StatelessWidget {
  const _SegmentList({required this.viewModel});

  final CaptureViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final segments = viewModel.segments;
    if (segments.isEmpty) {
      return Center(child: Text(L10nKeys.captureNoSegments.tr()));
    }
    final theme = Theme.of(context);
    return ListView.builder(
      itemCount: segments.length,
      itemBuilder: (context, index) {
        final segment = segments[index];
        final at = DateTime.fromMillisecondsSinceEpoch(segment.tStartMs);
        final transcribed = viewModel.transcriptionOf(segment.segmentId);
        return ListTile(
          dense: true,
          leading: const Icon(Icons.graphic_eq),
          // Le texte prime sur les métadonnées : c'est lui qu'on relit pendant
          // le test des 10 phrases, l'énergie et la durée ne servent qu'à
          // objectiver la calibration (MVP-15).
          title: transcribed == null
              ? Text(
                  L10nKeys.captureAwaitingTranscription.tr(),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.outline,
                    fontStyle: FontStyle.italic,
                  ),
                )
              : Text(transcribed.text, style: theme.textTheme.bodyLarge),
          subtitle: Text(
            L10nKeys.captureSegmentLine.tr(
              namedArgs: {
                'time': DateFormat.Hms().format(at),
                'duration': '${segment.durationMs}',
                'energy': segment.energyDbfs.toStringAsFixed(1),
              },
            ),
          ),
        );
      },
    );
  }
}
