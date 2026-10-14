import 'dart:convert';

enum ItemType { issue, suggestion, question, idea, betterSolution }

enum ItemCategory {
  statistics,
  ml,
  aiEngineering,
  dataEngineering,
  delivery,
  other,
}

enum Severity { high, medium, low }

class DocSource {
  const DocSource({required this.title, required this.url});

  final String title;
  final String url;

  Map<String, dynamic> toJson() => {'title': title, 'url': url};

  factory DocSource.fromJson(Map<String, dynamic> json) =>
      DocSource(title: json['title'] as String, url: json['url'] as String);
}

class AnalysisItem {
  const AnalysisItem({
    required this.type,
    required this.category,
    required this.severity,
    required this.title,
    required this.detail,
    required this.evidence,
    this.timestamp,
    this.sources = const [],
  });

  final ItemType type;
  final ItemCategory category;
  final Severity severity;
  final String title;
  final String detail;
  final String evidence;
  final Duration? timestamp;
  final List<DocSource> sources;

  bool get isIdea => type == ItemType.idea || type == ItemType.betterSolution;

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'category': category.name,
    'severity': severity.name,
    'title': title,
    'detail': detail,
    'evidence': evidence,
    'timestampMs': timestamp?.inMilliseconds,
    'sources': sources.map((s) => s.toJson()).toList(),
  };

  factory AnalysisItem.fromJson(Map<String, dynamic> json) => AnalysisItem(
    type: ItemType.values.byName(json['type'] as String),
    category: ItemCategory.values.byName(json['category'] as String),
    severity: Severity.values.byName(json['severity'] as String),
    title: json['title'] as String,
    detail: json['detail'] as String,
    evidence: json['evidence'] as String,
    timestamp: json['timestampMs'] == null
        ? null
        : Duration(milliseconds: json['timestampMs'] as int),
    sources: (json['sources'] as List<dynamic>? ?? [])
        .map((s) => DocSource.fromJson(s as Map<String, dynamic>))
        .toList(),
  );
}

class Analysis {
  const Analysis({
    required this.id,
    required this.createdAt,
    required this.model,
    required this.transcriptUpTo,
    required this.summary,
    required this.items,
  });

  final String id;
  final DateTime createdAt;
  final String model;
  final Duration transcriptUpTo;
  final String summary;
  final List<AnalysisItem> items;

  List<AnalysisItem> get issuesAndSuggestions =>
      items.where((item) => !item.isIdea).toList();

  List<AnalysisItem> get ideas => items.where((item) => item.isIdea).toList();
}

String encodeAnalysisItems(List<AnalysisItem> items) =>
    jsonEncode(items.map((i) => i.toJson()).toList());

List<AnalysisItem> decodeAnalysisItems(String json) =>
    (jsonDecode(json) as List<dynamic>)
        .map((i) => AnalysisItem.fromJson(i as Map<String, dynamic>))
        .toList();
