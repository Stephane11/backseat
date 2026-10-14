import 'dart:convert';

import '../../core/models/analysis.dart';
import '../../shared/formatting.dart';

class ParsedAnalysis {
  const ParsedAnalysis({required this.summary, required this.items});

  final String summary;
  final List<AnalysisItem> items;
}

/// Parses Claude's answer into cards. Tolerates the usual drift: Markdown
/// fences or a sentence around the object, unknown enum values, missing
/// optional fields. Returns null when there is no usable JSON object at all.
ParsedAnalysis? parseAnalysisJson(String text) {
  final start = text.indexOf('{');
  final end = text.lastIndexOf('}');
  if (start < 0 || end <= start) return null;

  final Object? decoded;
  try {
    decoded = jsonDecode(text.substring(start, end + 1));
  } on FormatException {
    return null;
  }
  if (decoded is! Map<String, dynamic>) return null;

  final summary = decoded['summary'];
  final rawItems = decoded['items'];
  if (summary is! String || rawItems is! List) return null;

  final items = <AnalysisItem>[
    for (final raw in rawItems)
      if (raw is Map<String, dynamic>) ?_parseItem(raw),
  ];
  return ParsedAnalysis(summary: summary.trim(), items: items);
}

AnalysisItem? _parseItem(Map<String, dynamic> json) {
  final title = (json['title'] as Object?)?.toString().trim() ?? '';
  final detail = (json['detail'] as Object?)?.toString().trim() ?? '';
  if (title.isEmpty && detail.isEmpty) return null;

  return AnalysisItem(
    type: _type(json['type']),
    category: _category(json['category']),
    severity: _severity(json['severity']),
    title: title,
    detail: detail,
    evidence: (json['evidence'] as Object?)?.toString().trim() ?? '',
    timestamp: parseHms(json['timestamp'] as String?),
    sources: [
      if (json['sources'] is List)
        for (final s in json['sources'] as List)
          if (s is Map &&
              s['url'] is String &&
              (Uri.tryParse(s['url'] as String)?.hasScheme ?? false))
            DocSource(
              title: (s['title'] as String?)?.trim().isNotEmpty == true
                  ? (s['title'] as String).trim()
                  : s['url'] as String,
              url: s['url'] as String,
            ),
    ],
  );
}

String _key(Object? v) =>
    (v?.toString() ?? '').toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');

ItemType _type(Object? v) => switch (_key(v)) {
  'issue' || 'risk' => ItemType.issue,
  'suggestion' => ItemType.suggestion,
  'question' => ItemType.question,
  'idea' => ItemType.idea,
  'bettersolution' => ItemType.betterSolution,
  _ => ItemType.suggestion,
};

ItemCategory _category(Object? v) => switch (_key(v)) {
  'statistics' || 'stats' => ItemCategory.statistics,
  'ml' || 'machinelearning' => ItemCategory.ml,
  'aiengineering' || 'ai' => ItemCategory.aiEngineering,
  'dataengineering' => ItemCategory.dataEngineering,
  'delivery' => ItemCategory.delivery,
  _ => ItemCategory.other,
};

Severity _severity(Object? v) => switch (_key(v)) {
  'high' => Severity.high,
  'low' => Severity.low,
  _ => Severity.medium,
};
