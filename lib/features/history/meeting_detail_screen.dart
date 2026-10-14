import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/models/analysis.dart';
import '../../core/models/meeting.dart';
import '../../core/models/settings_state.dart';
import '../../core/providers/app_providers.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_color_tokens.dart';
import '../../core/theme/app_radius.dart';
import '../../shared/formatting.dart';
import '../../shared/transcript_view.dart';
import '../analysis/analysis_flow.dart';
import '../analysis/analysis_results_sheet.dart';
import '../recording/model_download_service.dart';
import '../transcript/final_pass.dart';

String transcriptAsText(Meeting meeting) {
  final buffer = StringBuffer()
    ..writeln(meeting.title)
    ..writeln(
      '${formatRelativeDate(meeting.startedAt)} · ${formatTimer(meeting.duration)}',
    )
    ..writeln();
  for (final s in meeting.finalSegments) {
    buffer.writeln('[${formatHms(s.start)}] ${s.text}');
  }
  return buffer.toString();
}

class MeetingDetailScreen extends ConsumerStatefulWidget {
  const MeetingDetailScreen({super.key, required this.meetingId});

  final String meetingId;

  @override
  ConsumerState<MeetingDetailScreen> createState() =>
      _MeetingDetailScreenState();
}

class _MeetingDetailScreenState extends ConsumerState<MeetingDetailScreen> {
  final _jumpController = TranscriptJumpController();
  final _scrollController = ScrollController();
  late bool _checkDocs = ref.read(settingsProvider).checkDocsDefault;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _jumpTo(Duration ts) {
    final meeting = ref.read(meetingsProvider.notifier).byId(widget.meetingId);
    if (meeting == null) return;
    _jumpController.jumpToNearest(
      meeting.segments,
      ts,
      scrollController: _scrollController,
    );
  }

  Future<void> _onRename(String currentTitle) async {
    final controller = TextEditingController(text: currentTitle);
    final newTitle = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename meeting'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (newTitle != null && newTitle.trim().isNotEmpty) {
      await ref
          .read(meetingsProvider.notifier)
          .rename(widget.meetingId, newTitle.trim());
    }
  }

  Future<void> _onDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete meeting?'),
        content: const Text(
          'This removes the transcript, all analyses and any saved audio. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(meetingsProvider.notifier).delete(widget.meetingId);
      if (mounted) context.go(AppRoutes.home);
    }
  }

  void _onShareAction(String action, Meeting meeting) {
    switch (action) {
      case 'share_transcript':
        SharePlus.instance.share(
          ShareParams(text: transcriptAsText(meeting), subject: meeting.title),
        );
      case 'share_analysis':
        SharePlus.instance.share(
          ShareParams(
            text: analysisAsMarkdown(
              meeting.analyses.last,
              meetingTitle: meeting.title,
            ),
            subject: meeting.title,
          ),
        );
      case 'copy_transcript':
        Clipboard.setData(ClipboardData(text: transcriptAsText(meeting)));
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Transcript copied')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final meeting = ref.watch(
      meetingsProvider.select(
        (async) =>
            async.value?.where((m) => m.id == widget.meetingId).firstOrNull,
      ),
    );
    if (meeting == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final segments = meeting.finalSegments;

    return Scaffold(
      appBar: AppBar(
        title: Text(meeting.title),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.share_outlined),
            tooltip: 'Share',
            onSelected: (value) => _onShareAction(value, meeting),
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'share_transcript',
                child: Text('Share transcript'),
              ),
              if (meeting.analyses.isNotEmpty)
                const PopupMenuItem(
                  value: 'share_analysis',
                  child: Text('Share latest analysis'),
                ),
              const PopupMenuItem(
                value: 'copy_transcript',
                child: Text('Copy transcript'),
              ),
            ],
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'rename') _onRename(meeting.title);
              if (value == 'delete') _onDelete();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'rename', child: Text('Rename')),
              PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            sliver: SliverList.list(
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      '${formatRelativeDate(meeting.startedAt)} · '
                      '${formatTimer(meeting.duration)}',
                      style: textTheme.bodySmall?.copyWith(
                        color: tokens.textSecondary,
                      ),
                    ),
                    _SourceChip(source: meeting.transcriptSource),
                  ],
                ),
                if (meeting.contextNote != null) ...[
                  const SizedBox(height: 6),
                  Text(meeting.contextNote!, style: textTheme.bodySmall),
                ],
                _FinalPassPanel(meeting: meeting),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: segments.isEmpty
                            ? null
                            : () => startAnalysis(
                                context,
                                ref,
                                meetingId: meeting.id,
                                checkDocs: _checkDocs,
                                onTimestampTap: _jumpTo,
                              ),
                        icon: const Icon(Icons.auto_awesome),
                        label: Text(
                          meeting.analyses.isEmpty ? 'Analyse' : 'Re-analyse',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      avatar: const Icon(Icons.menu_book_outlined, size: 16),
                      label: const Text('Docs'),
                      tooltip: 'Check against docs',
                      selected: _checkDocs,
                      showCheckmark: false,
                      onSelected: (v) => setState(() => _checkDocs = v),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text('Analyses', style: textTheme.titleMedium),
                const SizedBox(height: 8),
                if (meeting.analyses.isEmpty)
                  Text(
                    'No analyses yet.',
                    style: textTheme.bodyMedium?.copyWith(
                      color: tokens.textSecondary,
                    ),
                  )
                else
                  for (final analysis in meeting.analyses.reversed)
                    _AnalysisRow(
                      analysis: analysis,
                      onTap: () => showAnalysisResultsSheet(
                        context,
                        analysis: analysis,
                        meetingTitle: meeting.title,
                        onTimestampTap: _jumpTo,
                      ),
                    ),
                const SizedBox(height: 24),
                Divider(color: tokens.border),
                const SizedBox(height: 12),
                Text('Transcript', style: textTheme.titleMedium),
                const SizedBox(height: 8),
                if (segments.isEmpty)
                  Text(
                    'No speech was transcribed in this meeting.',
                    style: textTheme.bodyMedium?.copyWith(
                      color: tokens.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
            sliver: SliverList.separated(
              itemCount: segments.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) => TranscriptLine(
                segment: segments[index],
                jumpController: _jumpController,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SourceChip extends StatelessWidget {
  const _SourceChip({required this.source});

  final TranscriptSource source;

  @override
  Widget build(BuildContext context) {
    final tokens = context.colors;
    final isFinal = source == TranscriptSource.finalPass;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: tokens.surfaceRaised,
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: Text(
        isFinal ? 'Final transcript' : 'Live draft',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: isFinal ? tokens.severityLow : tokens.textSecondary,
        ),
      ),
    );
  }
}

/// Shows the Whisper final pass: progress while it runs, a retry if it
/// failed, or the option to run it when the transcript is still the live
/// draft and the recording is still on the phone.
class _FinalPassPanel extends ConsumerWidget {
  const _FinalPassPanel({required this.meeting});

  final Meeting meeting;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final pass = ref.watch(finalPassProvider)[meeting.id];
    final settings = ref.watch(settingsProvider);
    final modelId = finalPassModelId(settings.finalPassModel);
    final downloads = ref.watch(modelDownloadsProvider);

    Widget panel(List<Widget> children) => Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: tokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );

    if (pass?.status == FinalPassStatus.running) {
      return panel([
        Text(
          'Improving transcript… ${(pass!.progress * 100).round()}%',
          style: textTheme.bodyMedium,
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(value: pass.progress, minHeight: 4),
        const SizedBox(height: 6),
        Text(
          'Re-transcribing the recording on-device with Whisper. You can '
          'keep using the app.',
          style: textTheme.bodySmall?.copyWith(color: tokens.textSecondary),
        ),
      ]);
    }

    final canImprove =
        meeting.transcriptSource == TranscriptSource.live &&
        meeting.audioPath != null &&
        !meeting.isLive &&
        meeting.finalSegments.isNotEmpty;
    if (!canImprove) return const SizedBox.shrink();

    final modelReady =
        modelId != null && downloads[modelId]?.status == ModelStatus.ready;
    return panel([
      Text(
        pass?.status == FinalPassStatus.failed
            ? pass!.error!
            : 'This is the live draft. An accurate on-device pass can clean '
                  'it up.',
        style: textTheme.bodyMedium,
      ),
      const SizedBox(height: 10),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (modelReady)
            FilledButton.tonal(
              onPressed: () => unawaited(
                ref.read(finalPassProvider.notifier).run(meeting.id),
              ),
              child: const Text('Improve transcript'),
            )
          else
            FilledButton.tonal(
              onPressed: () => context.push(AppRoutes.settings),
              child: Text(
                settings.finalPassModel == FinalPassModel.off
                    ? 'Choose a final-pass model'
                    : 'Download ${kAsrModels[modelId]!.displayName}',
              ),
            ),
          TextButton(
            onPressed: () =>
                ref.read(meetingsProvider.notifier).deleteAudio(meeting.id),
            child: const Text('Keep draft, delete audio'),
          ),
        ],
      ),
    ]);
  }
}

class _AnalysisRow extends StatelessWidget {
  const _AnalysisRow({required this.analysis, required this.onTap});

  final Analysis analysis;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final docsBacked = analysis.items.any((i) => i.sources.isNotEmpty);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: onTap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        title: Text(
          analysis.summary,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: textTheme.bodyMedium,
        ),
        subtitle: Text(
          '${analysis.items.length} items · up to '
          '${formatTimestamp(analysis.transcriptUpTo)}'
          '${docsBacked ? ' · docs-checked' : ''}',
          style: textTheme.labelSmall?.copyWith(color: tokens.textSecondary),
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}
