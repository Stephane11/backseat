import 'package:flutter/material.dart';

import '../core/models/segment.dart';
import '../core/theme/app_motion.dart';
import 'fade_slide_in.dart';
import 'formatting.dart';

/// Lets an Analysis results sheet jump the transcript behind it to the
/// segment nearest a card's timestamp (brief §4).
class TranscriptJumpController {
  final Map<String, GlobalKey> _keys = {};

  GlobalKey keyFor(String segmentId) =>
      _keys.putIfAbsent(segmentId, () => GlobalKey());

  /// [scrollController] lets it reach lines a lazy list hasn't built yet:
  /// it first jumps proportionally, then refines once the line is laid out.
  void jumpToNearest(
    List<Segment> segments,
    Duration timestamp, {
    ScrollController? scrollController,
  }) {
    if (segments.isEmpty) return;
    var index = 0;
    for (var i = 0; i < segments.length; i++) {
      if (segments[i].start <= timestamp) {
        index = i;
      } else {
        break;
      }
    }
    final id = segments[index].id;

    void reveal(BuildContext context) => Scrollable.ensureVisible(
      context,
      duration: AppMotion.duration,
      curve: AppMotion.curve,
      alignment: 0.1,
    );

    final context = _keys[id]?.currentContext;
    if (context != null) {
      reveal(context);
    } else if (scrollController != null && scrollController.hasClients) {
      final position = scrollController.position;
      scrollController.jumpTo(
        position.maxScrollExtent *
            index /
            (segments.length - 1).clamp(1, 1 << 30),
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final built = _keys[id]?.currentContext;
        if (built != null) reveal(built);
      });
    }
  }
}

class TranscriptView extends StatelessWidget {
  const TranscriptView({
    super.key,
    required this.segments,
    this.jumpController,
    this.scrollController,
    this.shrinkWrap = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
    this.emptyText = 'No transcript for this meeting.',
  });

  final List<Segment> segments;
  final TranscriptJumpController? jumpController;
  final ScrollController? scrollController;
  final bool shrinkWrap;
  final EdgeInsets padding;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    if (segments.isEmpty) {
      final textTheme = Theme.of(context).textTheme;
      final secondary = Theme.of(context).colorScheme.onSurfaceVariant;
      return Padding(
        padding: padding,
        child: Text(
          emptyText,
          style: textTheme.bodyMedium?.copyWith(color: secondary),
        ),
      );
    }

    return ListView.separated(
      controller: scrollController,
      padding: padding,
      shrinkWrap: shrinkWrap,
      physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
      itemCount: segments.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) => TranscriptLine(
        segment: segments[index],
        jumpController: jumpController,
      ),
    );
  }
}

/// One timestamped transcript line; partial (still being spoken) text is
/// shown in the secondary colour. New lines fade in.
class TranscriptLine extends StatelessWidget {
  TranscriptLine({required this.segment, this.jumpController})
    : super(key: jumpController?.keyFor(segment.id) ?? ValueKey(segment.id));

  final Segment segment;
  final TranscriptJumpController? jumpController;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;
    return FadeSlideIn(
      offset: 4,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 48,
            child: Text(
              formatTimestamp(segment.start),
              style: textTheme.labelSmall,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              segment.text,
              style: segment.isFinal
                  ? textTheme.bodyLarge
                  : textTheme.bodyLarge?.copyWith(color: secondary),
            ),
          ),
        ],
      ),
    );
  }
}
