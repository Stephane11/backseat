import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/models/analysis.dart';
import '../core/theme/app_color_tokens.dart';
import '../core/theme/app_radius.dart';
import 'category_chip.dart';
import 'formatting.dart';
import 'severity_dot.dart';

String itemTypeLabel(ItemType type) {
  return switch (type) {
    ItemType.issue => 'Issue',
    ItemType.suggestion => 'Suggestion',
    ItemType.question => 'Question',
    ItemType.idea => 'Idea',
    ItemType.betterSolution => 'Better solution',
  };
}

String analysisItemAsMarkdown(AnalysisItem item) {
  final buffer = StringBuffer()
    ..writeln(
      '**${item.title}** (${itemTypeLabel(item.type)}, ${item.severity.name})',
    )
    ..writeln()
    ..writeln(item.detail);
  if (item.evidence.isNotEmpty) {
    buffer
      ..writeln()
      ..writeln('> ${item.evidence}');
  }
  if (item.timestamp != null) {
    buffer.writeln('\n_${formatTimestamp(item.timestamp!)}_');
  }
  if (item.sources.isNotEmpty) {
    buffer.writeln('\nSources:');
    for (final s in item.sources) {
      buffer.writeln('- [${s.title}](${s.url})');
    }
  }
  return buffer.toString();
}

/// Opens a documentation page in an in-app browser tab (Custom Tabs).
Future<void> openDocSource(BuildContext context, DocSource source) async {
  final uri = Uri.tryParse(source.url);
  final ok =
      uri != null &&
      await launchUrl(
        uri,
        mode: LaunchMode.inAppBrowserView,
      ).catchError((_) => false);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text("Couldn't open that page")));
  }
}

class AnalysisItemCard extends StatelessWidget {
  const AnalysisItemCard({super.key, required this.item, this.onTimestampTap});

  final AnalysisItem item;
  final ValueChanged<Duration>? onTimestampTap;

  Future<void> _onSourcesTap(BuildContext context) async {
    if (item.sources.length == 1) {
      return openDocSource(context, item.sources.single);
    }
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final source in item.sources)
              ListTile(
                leading: const Icon(Icons.menu_book_outlined),
                title: Text(source.title),
                subtitle: Text(
                  Uri.tryParse(source.url)?.host ?? source.url,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  openDocSource(context, source);
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.colors;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SeverityDot(severity: item.severity),
                const SizedBox(width: 8),
                CategoryChip(category: item.category),
                const Spacer(),
                Text(itemTypeLabel(item.type), style: textTheme.labelSmall),
              ],
            ),
            const SizedBox(height: 10),
            Text(item.title, style: textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(item.detail, style: textTheme.bodyMedium),
            if (item.evidence.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(color: tokens.accent, width: 3),
                  ),
                  color: tokens.surfaceRaised,
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                ),
                child: Text(
                  item.evidence,
                  style: textTheme.bodySmall?.copyWith(
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
            if (item.sources.isNotEmpty) ...[
              const SizedBox(height: 10),
              ActionChip(
                avatar: Icon(
                  Icons.verified_outlined,
                  size: 16,
                  color: tokens.severityLow,
                ),
                label: Text(
                  item.sources.length == 1
                      ? 'Verified in docs'
                      : 'Verified in docs (${item.sources.length})',
                ),
                visualDensity: VisualDensity.compact,
                onPressed: () => _onSourcesTap(context),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                if (item.timestamp != null)
                  InkWell(
                    onTap: onTimestampTap == null
                        ? null
                        : () => onTimestampTap!(item.timestamp!),
                    borderRadius: BorderRadius.circular(AppRadius.chip),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 4,
                        horizontal: 4,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.schedule,
                            size: 14,
                            color: tokens.textSecondary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            formatTimestamp(item.timestamp!),
                            style: textTheme.labelSmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.copy_outlined, size: 18),
                  tooltip: 'Copy card',
                  onPressed: () {
                    Clipboard.setData(
                      ClipboardData(text: analysisItemAsMarkdown(item)),
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Copied to clipboard')),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
