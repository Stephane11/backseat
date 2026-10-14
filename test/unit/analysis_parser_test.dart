import 'package:flutter_test/flutter_test.dart';

import 'package:backseat/core/models/analysis.dart';
import 'package:backseat/features/analysis/analysis_parser.dart';

void main() {
  const valid = '''
{
  "summary": "Churn model review.",
  "items": [
    {
      "type": "issue",
      "category": "statistics",
      "severity": "high",
      "title": "Random split may leak",
      "detail": "Use a time-based split.",
      "evidence": "the holdout set is a random split",
      "timestamp": "00:00:27",
      "sources": []
    },
    {
      "type": "better_solution",
      "category": "data_engineering",
      "severity": "low",
      "title": "Use Auto Loader file notifications",
      "detail": "Cheaper than directory listing.",
      "evidence": "lots of small files",
      "timestamp": null,
      "sources": [
        {"title": "Auto Loader options", "url": "https://learn.microsoft.com/azure/databricks/ingestion/auto-loader/options"}
      ]
    }
  ]
}''';

  test('parses the documented schema', () {
    final parsed = parseAnalysisJson(valid)!;
    expect(parsed.summary, 'Churn model review.');
    expect(parsed.items, hasLength(2));

    final first = parsed.items[0];
    expect(first.type, ItemType.issue);
    expect(first.category, ItemCategory.statistics);
    expect(first.severity, Severity.high);
    expect(first.timestamp, const Duration(seconds: 27));
    expect(first.sources, isEmpty);

    final second = parsed.items[1];
    expect(second.type, ItemType.betterSolution);
    expect(second.isIdea, isTrue);
    expect(second.category, ItemCategory.dataEngineering);
    expect(second.timestamp, isNull);
    expect(second.sources.single.title, 'Auto Loader options');
  });

  test('tolerates Markdown fences and surrounding prose', () {
    final parsed = parseAnalysisJson(
      'Here is the analysis:\n```json\n$valid\n```\nHope this helps.',
    );
    expect(parsed?.items, hasLength(2));
  });

  test('maps unknown enum values to safe defaults', () {
    final parsed = parseAnalysisJson('''
{"summary": "s", "items": [{"type": "observation", "category": "finance",
 "severity": "critical", "title": "t", "detail": "d", "evidence": "e",
 "timestamp": "12:34"}]}''')!;
    final item = parsed.items.single;
    expect(item.type, ItemType.suggestion);
    expect(item.category, ItemCategory.other);
    expect(item.severity, Severity.medium);
    expect(item.timestamp, const Duration(minutes: 12, seconds: 34));
  });

  test('drops empty items and sources without a valid URL', () {
    final parsed = parseAnalysisJson('''
{"summary": "s", "items": [
  {"type": "issue"},
  {"title": "Keep", "detail": "d", "sources": [{"title": "x", "url": "not a url"}]}
]}''')!;
    expect(parsed.items.single.title, 'Keep');
    expect(parsed.items.single.sources, isEmpty);
  });

  test('returns null for non-JSON or wrong shape', () {
    expect(parseAnalysisJson('Sorry, I cannot help.'), isNull);
    expect(parseAnalysisJson('{"summary": "s", "items": [}'), isNull);
    expect(parseAnalysisJson('{"items": []}'), isNull);
  });

  test('round-trips through the stored items JSON', () {
    final items = parseAnalysisJson(valid)!.items;
    final restored = decodeAnalysisItems(encodeAnalysisItems(items));
    expect(restored[1].sources.single.url, items[1].sources.single.url);
    expect(restored[0].timestamp, items[0].timestamp);
  });
}
