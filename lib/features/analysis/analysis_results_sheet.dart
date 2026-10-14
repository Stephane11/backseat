import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/models/analysis.dart';
import '../../core/theme/app_color_tokens.dart';
import '../../core/theme/app_motion.dart';
import '../../shared/analysis_item_card.dart';
import '../../shared/fade_slide_in.dart';
import '../../shared/formatting.dart';

enum _ResultsFilter { issues, ideas }

String analysisAsMarkdown(Analysis analysis, {String? meetingTitle}) {
  final buffer = StringBuffer()
    ..writeln(
      '# ${meetingTitle ?? 'Analysis'} — ${formatRelativeDate(analysis.createdAt)}',
    )
    ..writeln()
    ..writeln(analysis.summary)
    ..writeln();
  void section(String title, List<AnalysisItem> items) {
    if (items.isEmpty) return;
    buffer
      ..writeln('## $title')
      ..writeln();
    for (final item in items) {
      buffer
        ..writeln(analysisItemAsMarkdown(item))
        ..writeln();
    }
  }

  section('Issues & suggestions', analysis.issuesAndSuggestions);
  section('Ideas & better solutions', analysis.ideas);
  return buffer.toString();
}

/// The body of an analysis: summary, Issues/Ideas switch and cards. Used both
/// inside the live "Analysing…" sheet once results arrive and when opening a
/// past analysis.
class AnalysisResultsView extends StatefulWidget {
  const AnalysisResultsView({
    super.key,
    required this.analysis,
    this.meetingTitle,
    this.scrollController,
    this.onTimestampTap,
    this.notice,
  });

  final Analysis analysis;
  final String? meetingTitle;
  final ScrollController? scrollController;
  final ValueChanged<Duration>? onTimestampTap;

  /// Optional banner text, e.g. that a long transcript was trimmed.
  final String? notice;

  @override
  State<AnalysisResultsView> createState() => _AnalysisResultsViewState();
}

class _AnalysisResultsViewState extends State<AnalysisResultsView> {
  late _ResultsFilter _filter =
      widget.analysis.issuesAndSuggestions.isEmpty &&
          widget.analysis.ideas.isNotEmpty
      ? _ResultsFilter.ideas
      : _ResultsFilter.issues;

  void _onTimestampTap(Duration ts) {
    final callback = widget.onTimestampTap;
    if (callback == null) return;
    // Close the sheet first so the transcript behind it is visible.
    Navigator.of(context).maybePop();
    WidgetsBinding.instance.addPostFrameCallback((_) => callback(ts));
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final analysis = widget.analysis;
    final items = _filter == _ResultsFilter.issues
        ? analysis.issuesAndSuggestions
        : analysis.ideas;
    final markdown = analysisAsMarkdown(
      analysis,
      meetingTitle: widget.meetingTitle,
    );

    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        Row(
          children: [
            Expanded(child: Text('Analysis', style: textTheme.headlineSmall)),
            IconButton(
              icon: const Icon(Icons.copy_all_outlined),
              tooltip: 'Copy all as Markdown',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: markdown));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Copied all results as Markdown'),
                  ),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.share_outlined),
              tooltip: 'Share',
              onPressed: () => SharePlus.instance.share(
                ShareParams(text: markdown, subject: widget.meetingTitle),
              ),
            ),
          ],
        ),
        Text(
          '${formatRelativeDate(analysis.createdAt)} · up to '
          '${formatTimestamp(analysis.transcriptUpTo)} · ${analysis.model}',
          style: textTheme.labelSmall?.copyWith(color: tokens.textSecondary),
        ),
        if (widget.notice != null) ...[
          const SizedBox(height: 12),
          _Notice(text: widget.notice!),
        ],
        const SizedBox(height: 12),
        Text(analysis.summary, style: textTheme.bodyMedium),
        const SizedBox(height: 16),
        SegmentedButton<_ResultsFilter>(
          segments: [
            ButtonSegment(
              value: _ResultsFilter.issues,
              label: Text(
                'Issues & suggestions (${analysis.issuesAndSuggestions.length})',
              ),
            ),
            ButtonSegment(
              value: _ResultsFilter.ideas,
              label: Text('Ideas (${analysis.ideas.length})'),
            ),
          ],
          selected: {_filter},
          showSelectedIcon: false,
          onSelectionChanged: (value) => setState(() => _filter = value.first),
        ),
        const SizedBox(height: 16),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              analysis.items.isEmpty
                  ? 'Nothing worth flagging yet. Keep the meeting going and '
                        'analyse again later.'
                  : 'Nothing in this category for this analysis.',
              style: textTheme.bodyMedium?.copyWith(
                color: tokens.textSecondary,
              ),
            ),
          )
        else
          for (final (i, item) in items.indexed)
            FadeSlideIn(
              key: ValueKey('${_filter.name}-$i'),
              delay: AppMotion.cardStagger * i,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: AnalysisItemCard(
                  item: item,
                  onTimestampTap: widget.onTimestampTap == null
                      ? null
                      : _onTimestampTap,
                ),
              ),
            ),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = context.colors;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tokens.surfaceRaised,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: tokens.severityMedium),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}

/// Drag handle + scrollable body, shared by all analysis sheets.
class SheetFrame extends StatelessWidget {
  const SheetFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 12),
        Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: context.colors.border,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}

Future<void> showDraggableSheet(
  BuildContext context, {
  required Widget Function(BuildContext, ScrollController) builder,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => DraggableScrollableSheet(
      initialChildSize: 0.8,
      minChildSize: 0.4,
      maxChildSize: 1,
      expand: false,
      builder: (context, scrollController) =>
          SheetFrame(child: builder(context, scrollController)),
    ),
  );
}

Future<void> showAnalysisResultsSheet(
  BuildContext context, {
  required Analysis analysis,
  String? meetingTitle,
  ValueChanged<Duration>? onTimestampTap,
}) {
  return showDraggableSheet(
    context,
    builder: (context, scrollController) => AnalysisResultsView(
      analysis: analysis,
      meetingTitle: meetingTitle,
      scrollController: scrollController,
      onTimestampTap: onTimestampTap,
    ),
  );
}
