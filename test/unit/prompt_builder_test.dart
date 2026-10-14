import 'package:flutter_test/flutter_test.dart';

import 'package:backseat/core/models/segment.dart';
import 'package:backseat/features/analysis/prompt_builder.dart';

Segment seg(int startSec, String text, {bool isFinal = true}) => Segment(
  id: 's$startSec',
  start: Duration(seconds: startSec),
  end: Duration(seconds: startSec + 5),
  text: text,
  isFinal: isFinal,
);

List<Map<String, dynamic>> userContent(BuiltAnalysisRequest r) =>
    ((r.body['messages'] as List).single['content'] as List)
        .cast<Map<String, dynamic>>();

void main() {
  const options = AnalysisRequestOptions(model: 'claude-sonnet-5-5');

  test('includes contexts, vocabulary and timestamped final lines only', () {
    final r = buildAnalysisRequest(
      systemPrompt: 'SYSTEM',
      docsAddendum: 'DOCS',
      input: AnalysisInput(
        segments: [
          seg(5, 'we use accuracy'),
          seg(754, 'random split'),
          seg(800, 'still talking', isFinal: false),
        ],
        meetingTitle: 'Churn review',
        meetingContext: 'Marketing stakeholders',
        globalContext: 'I own the churn model',
        vocabulary: ['Unity Catalog', 'MLflow'],
      ),
      options: options,
    );
    final content = userContent(r);
    final context = content.first['text'] as String;
    expect(context, contains('Churn review'));
    expect(context, contains('Marketing stakeholders'));
    expect(context, contains('I own the churn model'));
    expect(context, contains('Unity Catalog, MLflow'));

    final transcript = content
        .skip(1)
        .take(content.length - 2)
        .map((b) => b['text'])
        .join();
    expect(transcript, contains('[00:00:05] we use accuracy'));
    expect(transcript, contains('[00:12:34] random split'));
    expect(transcript, isNot(contains('still talking')));
    expect(r.transcriptUpTo, const Duration(seconds: 759));
    expect(r.trimmedBefore, isNull);
  });

  test('splits the transcript on 10-minute boundaries with a cache '
      'breakpoint on the last block', () {
    final r = buildAnalysisRequest(
      systemPrompt: 'SYSTEM',
      docsAddendum: 'DOCS',
      input: AnalysisInput(
        segments: [seg(10, 'a'), seg(610, 'b'), seg(1300, 'c')],
      ),
      options: options,
    );
    final content = userContent(r);
    // context + 3 transcript blocks + instruction
    expect(content, hasLength(5));
    expect(content[3]['cache_control'], {'type': 'ephemeral'});
    expect(content[1].containsKey('cache_control'), isFalse);
    expect(content.last.containsKey('cache_control'), isFalse);

    // Adding later speech leaves earlier blocks byte-identical.
    final grown = buildAnalysisRequest(
      systemPrompt: 'SYSTEM',
      docsAddendum: 'DOCS',
      input: AnalysisInput(
        segments: [seg(10, 'a'), seg(610, 'b'), seg(1300, 'c'), seg(1900, 'd')],
      ),
      options: options,
    );
    expect(userContent(grown)[1]['text'], content[1]['text']);
    expect(userContent(grown)[2]['text'], content[2]['text']);
  });

  test('docs off: no tools and system is the base prompt only', () {
    final r = buildAnalysisRequest(
      systemPrompt: 'SYSTEM',
      docsAddendum: 'DOCS',
      input: AnalysisInput(segments: [seg(1, 'x')]),
      options: options,
    );
    expect(r.body.containsKey('tools'), isFalse);
    final system = r.body['system'] as List;
    expect(system, hasLength(1));
    expect(system.single['cache_control'], {'type': 'ephemeral'});
    expect(r.body['fallbacks'], 'default');
    expect(r.body['model'], 'claude-sonnet-5-5');
  });

  test('docs on: web search + fetch restricted to the approved domains', () {
    final r = buildAnalysisRequest(
      systemPrompt: 'SYSTEM',
      docsAddendum: 'DOCS',
      input: AnalysisInput(segments: [seg(1, 'x')]),
      options: const AnalysisRequestOptions(
        model: 'claude-opus-5-5',
        checkDocs: true,
        docDomains: ['learn.microsoft.com', 'docs.databricks.com'],
        maxDocLookups: 3,
      ),
    );
    final tools = (r.body['tools'] as List).cast<Map<String, dynamic>>();
    expect(tools.map((t) => t['type']), [
      'web_search_20260209',
      'web_fetch_20260209',
    ]);
    for (final t in tools) {
      expect(t['allowed_domains'], [
        'learn.microsoft.com',
        'docs.databricks.com',
      ]);
      expect(t['max_uses'], 3);
    }
    final system = (r.body['system'] as List).cast<Map<String, dynamic>>();
    expect(system.map((s) => s['text']), ['SYSTEM', 'DOCS']);
    expect(system.last['cache_control'], isNotNull);
  });

  test('trims the oldest segments past the cap and says so', () {
    final segments = [for (var i = 0; i < 100; i++) seg(i * 10, 'x' * 50)];
    final r = buildAnalysisRequest(
      systemPrompt: 'SYSTEM',
      docsAddendum: 'DOCS',
      input: AnalysisInput(segments: segments),
      options: const AnalysisRequestOptions(
        model: 'claude-sonnet-5-5',
        maxTranscriptChars: 1000,
      ),
    );
    expect(r.trimmedBefore, isNotNull);
    expect(r.trimmedBefore! > Duration.zero, isTrue);
    expect(r.transcriptUpTo, segments.last.end);
    expect(userContent(r).last['text'], contains('earlier parts are omitted'));
  });

  test('retry adds the JSON-only reminder', () {
    final r = buildAnalysisRequest(
      systemPrompt: 'SYSTEM',
      docsAddendum: 'DOCS',
      input: AnalysisInput(segments: [seg(1, 'x')]),
      options: const AnalysisRequestOptions(
        model: 'claude-sonnet-5-5',
        retryReminder: true,
      ),
    );
    expect(userContent(r).last['text'], contains('ONLY the JSON object'));
  });
}
