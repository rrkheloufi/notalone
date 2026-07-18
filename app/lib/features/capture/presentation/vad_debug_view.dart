import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:notalone/core/l10n/l10n_keys.dart';
import 'package:notalone/core/result/failure.dart';
import 'package:notalone/features/capture/domain/audio_level.dart';
import 'package:notalone/features/capture/domain/capture_failure.dart';
import 'package:notalone/features/capture/presentation/vad_debug_viewmodel.dart';

/// Écran de debug jetable du spike MVP-02 : vumètre RMS, probabilité VAD,
/// segments détectés. Supprimé quand MVP-08 industrialisera le pipeline.
class VadDebugView extends StatefulWidget {
  const VadDebugView({required this.viewModel, super.key});

  final VadDebugViewModel viewModel;

  @override
  State<VadDebugView> createState() => _VadDebugViewState();
}

class _VadDebugViewState extends State<VadDebugView> {
  @override
  void dispose() {
    widget.viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = widget.viewModel;
    return Scaffold(
      appBar: AppBar(title: Text(L10nKeys.vadDebugTitle.tr())),
      body: ListenableBuilder(
        listenable: Listenable.merge([
          viewModel,
          viewModel.startCommand,
          viewModel.stopCommand,
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
                _LevelMeter(levelDbfs: viewModel.levelDbfs),
                const SizedBox(height: 12),
                _ProbabilityRow(
                  probability: viewModel.speechProbability,
                  speechActive: viewModel.isSpeechActive,
                ),
                const SizedBox(height: 16),
                _StartStopButton(viewModel: viewModel),
                const SizedBox(height: 16),
                Text(
                  L10nKeys.vadDebugSegmentsTitle.tr(),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Expanded(child: _SegmentList(viewModel: viewModel)),
              ],
            ),
          );
        },
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
    final message = failure is MicPermissionFailure
        ? L10nKeys.vadDebugMicPermissionError.tr()
        : failure.message;
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

class _LevelMeter extends StatelessWidget {
  const _LevelMeter({required this.levelDbfs});

  final double levelDbfs;

  @override
  Widget build(BuildContext context) {
    // Vumètre calé sur [-60 dBFS ; 0 dBFS].
    final normalized = ((levelDbfs + 60) / 60).clamp(0.0, 1.0);
    final label = levelDbfs <= AudioLevel.floorDbfs
        ? '–∞'
        : levelDbfs.toStringAsFixed(1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${L10nKeys.vadDebugLevel.tr()} : $label dBFS'),
        const SizedBox(height: 4),
        LinearProgressIndicator(value: normalized, minHeight: 12),
      ],
    );
  }
}

class _ProbabilityRow extends StatelessWidget {
  const _ProbabilityRow({
    required this.probability,
    required this.speechActive,
  });

  final double probability;
  final bool speechActive;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(
          Icons.circle,
          size: 16,
          color: speechActive ? scheme.primary : scheme.outlineVariant,
        ),
        const SizedBox(width: 8),
        Text(
          '${L10nKeys.vadDebugProbability.tr()} : '
          '${probability.toStringAsFixed(2)}',
        ),
        if (speechActive) ...[
          const SizedBox(width: 8),
          Text(
            L10nKeys.vadDebugSpeechActive.tr(),
            style: TextStyle(color: scheme.primary),
          ),
        ],
      ],
    );
  }
}

class _StartStopButton extends StatelessWidget {
  const _StartStopButton({required this.viewModel});

  final VadDebugViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final busy =
        viewModel.startCommand.running || viewModel.stopCommand.running;
    if (viewModel.isCapturing) {
      return FilledButton.icon(
        onPressed: busy
            ? null
            : () => unawaited(viewModel.stopCommand.execute()),
        icon: const Icon(Icons.stop),
        label: Text(L10nKeys.vadDebugStop.tr()),
      );
    }
    return FilledButton.icon(
      onPressed: busy
          ? null
          : () => unawaited(viewModel.startCommand.execute()),
      icon: const Icon(Icons.mic),
      label: Text(L10nKeys.vadDebugStart.tr()),
    );
  }
}

class _SegmentList extends StatelessWidget {
  const _SegmentList({required this.viewModel});

  final VadDebugViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final segments = viewModel.segments;
    if (segments.isEmpty) {
      return Center(child: Text(L10nKeys.vadDebugNoSegments.tr()));
    }
    return ListView.builder(
      itemCount: segments.length,
      itemBuilder: (context, index) {
        // Dernier segment en tête de liste.
        final number = segments.length - index;
        final segment = segments[number - 1];
        return ListTile(
          dense: true,
          leading: Text('#$number'),
          title: Text(
            L10nKeys.vadDebugSegmentLine.tr(
              namedArgs: {
                'start': (segment.tStartMs / 1000).toStringAsFixed(1),
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
