import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/analysis.dart';
import '../../core/providers/app_providers.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_color_tokens.dart';
import '../../core/theme/app_radius.dart';
import '../../shared/formatting.dart';
import 'analysis_results_sheet.dart';
import 'analysis_service.dart';
import 'claude_client.dart';

/// Entry point for every Analyse / Re-analyse tap: checks the API key, shows
/// the one-time privacy notice, then opens the streaming results sheet.
Future<void> startAnalysis(
  BuildContext context,
  WidgetRef ref, {
  required String meetingId,
  required bool checkDocs,
  ValueChanged<Duration>? onTimestampTap,
}) async {
  if (!ref.read(settingsProvider).hasApiKey) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Add your Claude API key to analyse meetings.'),
        action: SnackBarAction(
          label: 'Settings',
          onPressed: () => context.push(AppRoutes.settings),
        ),
      ),
    );
    return;
  }

  if (!ref.read(privacyNoticeAcknowledgedProvider)) {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Before your first analysis'),
        content: const Text(
          'Analyse sends the transcript text, your context notes and custom '
          "vocabulary to Anthropic's Claude API. Audio never leaves your "
          'phone.\n\nWith "Check against docs" on, Claude may also search '
          'and read the approved documentation sites.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    ref.read(privacyNoticeAcknowledgedProvider.notifier).acknowledge();
  }

  if (!context.mounted) return;
  HapticFeedback.mediumImpact();
  await showDraggableSheet(
    context,
    builder: (context, scrollController) => AnalysisRunView(
      meetingId: meetingId,
      checkDocs: checkDocs,
      scrollController: scrollController,
      onTimestampTap: onTimestampTap,
    ),
  );
}

sealed class _RunState {
  const _RunState();
}

class _Running extends _RunState {
  const _Running(this.status, this.lookups);
  final String status;
  final List<String> lookups;
}

class _Done extends _RunState {
  const _Done(this.analysis, this.notice);
  final Analysis analysis;
  final String? notice;
}

class _Failed extends _RunState {
  const _Failed(this.error);
  final ClaudeApiException error;
}

class _Raw extends _RunState {
  const _Raw(this.text);
  final String text;
}

class AnalysisRunView extends ConsumerStatefulWidget {
  const AnalysisRunView({
    super.key,
    required this.meetingId,
    required this.checkDocs,
    this.scrollController,
    this.onTimestampTap,
  });

  final String meetingId;
  final bool checkDocs;
  final ScrollController? scrollController;
  final ValueChanged<Duration>? onTimestampTap;

  @override
  ConsumerState<AnalysisRunView> createState() => _AnalysisRunViewState();
}

class _AnalysisRunViewState extends ConsumerState<AnalysisRunView> {
  _RunState _state = const _Running('Reading the transcript…', []);
  CancelToken? _cancelToken;
  final _stopwatch = Stopwatch();
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  @override
  void dispose() {
    _cancelToken?.cancel();
    _ticker?.cancel();
    super.dispose();
  }

  String _describe(StreamStatus status) => switch (status) {
    StatusThinking() => 'Thinking it through…',
    StatusSearching(:final query) => 'Checking docs: “$query”…',
    StatusReading(:final url) => 'Reading ${Uri.tryParse(url)?.host ?? url}…',
    StatusWriting() => 'Writing feedback…',
  };

  Future<void> _run() async {
    final meeting = ref.read(meetingsProvider.notifier).byId(widget.meetingId);
    if (meeting == null) return;
    final cancelToken = _cancelToken = CancelToken();
    final lookups = <String>[];
    setState(() => _state = const _Running('Reading the transcript…', []));
    _stopwatch
      ..reset()
      ..start();
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });

    try {
      final outcome = await ref
          .read(analysisServiceProvider)
          .analyse(
            meeting,
            checkDocs: widget.checkDocs,
            cancelToken: cancelToken,
            onStatus: (status) {
              if (!mounted) return;
              if (status is StatusSearching) lookups.add(status.query);
              final text = _describe(status);
              final current = _state;
              if (current is _Running && current.status == text) return;
              setState(() => _state = _Running(text, [...lookups]));
            },
          );
      if (!mounted) return;
      switch (outcome) {
        case AnalysisSucceeded(:final analysis, :final trimmedBefore):
          await ref
              .read(meetingsProvider.notifier)
              .addAnalysis(widget.meetingId, analysis);
          if (!mounted) return;
          HapticFeedback.lightImpact();
          setState(
            () => _state = _Done(
              analysis,
              trimmedBefore == null
                  ? null
                  : 'This meeting is very long: the transcript before '
                        '${formatTimestamp(trimmedBefore)} was left out of '
                        'this analysis.',
            ),
          );
        case AnalysisUnparseable(:final rawText):
          setState(() => _state = _Raw(rawText));
      }
    } on ClaudeApiException catch (e) {
      if (!mounted || e.kind == ClaudeErrorKind.cancelled) return;
      setState(() => _state = _Failed(e));
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _state = const _Failed(
          ClaudeApiException(
            ClaudeErrorKind.server,
            'Something went wrong while analysing. Try again.',
          ),
        ),
      );
    } finally {
      _stopwatch.stop();
      _ticker?.cancel();
    }
  }

  @override
  Widget build(BuildContext context) {
    final meetingTitle = ref
        .read(meetingsProvider.notifier)
        .byId(widget.meetingId)
        ?.title;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: switch (_state) {
        _Running(:final status, :final lookups) => _RunningView(
          key: const ValueKey('running'),
          status: status,
          lookups: lookups,
          elapsed: _stopwatch.elapsed,
          checkDocs: widget.checkDocs,
          scrollController: widget.scrollController,
        ),
        _Done(:final analysis, :final notice) => AnalysisResultsView(
          key: const ValueKey('done'),
          analysis: analysis,
          meetingTitle: meetingTitle,
          scrollController: widget.scrollController,
          onTimestampTap: widget.onTimestampTap,
          notice: notice,
        ),
        _Failed(:final error) => _ErrorView(
          key: const ValueKey('failed'),
          error: error,
          scrollController: widget.scrollController,
          onRetry: _run,
        ),
        _Raw(:final text) => _RawView(
          key: const ValueKey('raw'),
          text: text,
          scrollController: widget.scrollController,
          onRetry: _run,
        ),
      },
    );
  }
}

class _RunningView extends StatelessWidget {
  const _RunningView({
    super.key,
    required this.status,
    required this.lookups,
    required this.elapsed,
    required this.checkDocs,
    this.scrollController,
  });

  final String status;
  final List<String> lookups;
  final Duration elapsed;
  final bool checkDocs;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    final tokens = context.colors;
    final textTheme = Theme.of(context).textTheme;
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        Text('Analysing', style: textTheme.headlineSmall),
        const SizedBox(height: 16),
        Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: tokens.accent,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Text(
                  status,
                  key: ValueKey(status),
                  style: textTheme.bodyMedium,
                ),
              ),
            ),
            Text(
              '${elapsed.inSeconds}s',
              style: textTheme.labelSmall?.copyWith(
                color: tokens.textSecondary,
              ),
            ),
          ],
        ),
        if (checkDocs) ...[
          const SizedBox(height: 8),
          Text(
            lookups.isEmpty
                ? 'Doc lookups on: this can take 30–60 s.'
                : 'Looked up: ${lookups.join(' · ')}',
            style: textTheme.labelSmall?.copyWith(color: tokens.textSecondary),
          ),
        ],
        const SizedBox(height: 24),
        for (var i = 0; i < 3; i++) const _SkeletonCard(),
      ],
    );
  }
}

/// Placeholder card that gently pulses while results stream in.
class _SkeletonCard extends StatefulWidget {
  const _SkeletonCard();

  @override
  State<_SkeletonCard> createState() => _SkeletonCardState();
}

class _SkeletonCardState extends State<_SkeletonCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
    lowerBound: 0.45,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _controller.value = 0.7;
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.colors;
    Widget bar(double widthFactor, double height) => FractionallySizedBox(
      widthFactor: widthFactor,
      alignment: Alignment.centerLeft,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: tokens.surfaceRaised,
          borderRadius: BorderRadius.circular(6),
        ),
      ),
    );
    return FadeTransition(
      opacity: _controller,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: tokens.surface,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: tokens.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            bar(0.3, 14),
            const SizedBox(height: 12),
            bar(0.8, 20),
            const SizedBox(height: 10),
            bar(1, 12),
            const SizedBox(height: 6),
            bar(0.9, 12),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({
    super.key,
    required this.error,
    required this.onRetry,
    this.scrollController,
  });

  final ClaudeApiException error;
  final VoidCallback onRetry;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    final tokens = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final goToSettings = switch (error.kind) {
      ClaudeErrorKind.noApiKey ||
      ClaudeErrorKind.auth ||
      ClaudeErrorKind.permission ||
      ClaudeErrorKind.webSearchDisabled => true,
      _ => false,
    };
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      children: [
        Icon(
          error.kind == ClaudeErrorKind.network
              ? Icons.wifi_off_outlined
              : Icons.error_outline,
          size: 40,
          color: tokens.severityHigh,
        ),
        const SizedBox(height: 12),
        Text(
          "Analysis didn't complete",
          style: textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          error.message,
          style: textTheme.bodyMedium?.copyWith(color: tokens.textSecondary),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (goToSettings)
              OutlinedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  context.push(AppRoutes.settings);
                },
                child: const Text('Open Settings'),
              ),
            if (goToSettings) const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ],
    );
  }
}

class _RawView extends StatelessWidget {
  const _RawView({
    super.key,
    required this.text,
    required this.onRetry,
    this.scrollController,
  });

  final String text;
  final VoidCallback onRetry;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Analysis (raw)', style: textTheme.headlineSmall),
            ),
            IconButton(
              icon: const Icon(Icons.copy_outlined),
              tooltip: 'Copy',
              onPressed: () => Clipboard.setData(ClipboardData(text: text)),
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Retry',
              onPressed: onRetry,
            ),
          ],
        ),
        Text(
          "Claude's answer couldn't be turned into cards, so here it is as "
          "plain text. It wasn't saved.",
          style: textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        SelectableText(text, style: textTheme.bodyMedium),
      ],
    );
  }
}
