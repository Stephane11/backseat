import '../../core/models/segment.dart';
import '../../shared/formatting.dart';

/// Everything about one meeting that goes into an analysis request.
class AnalysisInput {
  const AnalysisInput({
    required this.segments,
    this.meetingTitle = '',
    this.meetingContext = '',
    this.globalContext = '',
    this.vocabulary = const [],
  });

  /// Final segments only, in time order.
  final List<Segment> segments;
  final String meetingTitle;
  final String meetingContext;
  final String globalContext;
  final List<String> vocabulary;
}

class AnalysisRequestOptions {
  const AnalysisRequestOptions({
    required this.model,
    this.checkDocs = false,
    this.docDomains = const [],
    this.maxDocLookups = 5,
    this.maxTranscriptChars = 400000,
    this.retryReminder = false,
  });

  final String model;
  final bool checkDocs;
  final List<String> docDomains;
  final int maxDocLookups;

  /// Input cap (~100k tokens). A 2-hour meeting is ~120k characters, so this
  /// only bites on unusually long sessions.
  final int maxTranscriptChars;

  /// Set on the single retry after a response that wasn't valid JSON.
  final bool retryReminder;
}

class BuiltAnalysisRequest {
  const BuiltAnalysisRequest({
    required this.body,
    required this.transcriptUpTo,
    required this.trimmedBefore,
  });

  /// JSON body for `POST /v1/messages` (without `stream`).
  final Map<String, dynamic> body;
  final Duration transcriptUpTo;

  /// Start of the earliest segment included when the oldest part had to be
  /// dropped to respect the cap; null when the whole transcript was sent.
  final Duration? trimmedBefore;
}

/// Transcript blocks are cut on fixed 10-minute boundaries so earlier blocks
/// stay byte-identical as the meeting grows: a repeated Analyse tap then
/// reads them from the prompt cache and only pays for the new tail. A
/// 2-hour meeting is 12 blocks, inside the cache's 20-block lookback.
const transcriptBlockSpan = Duration(minutes: 10);

const _instruction =
    'Analyse the meeting transcript above and return the JSON object '
    'described in your instructions.';

const _retryInstruction =
    'Your previous answer could not be parsed. Return ONLY the JSON object '
    'that matches the schema: no prose, no Markdown fences, nothing before '
    'the opening brace or after the closing brace. Keep it concise.';

BuiltAnalysisRequest buildAnalysisRequest({
  required String systemPrompt,
  required String docsAddendum,
  required AnalysisInput input,
  required AnalysisRequestOptions options,
}) {
  var segments = input.segments
      .where((s) => s.isFinal && s.text.trim().isNotEmpty)
      .toList();
  Duration? trimmedBefore;
  var total = segments.fold<int>(0, (n, s) => n + _line(s).length + 1);
  if (total > options.maxTranscriptChars) {
    var drop = 0;
    while (drop < segments.length - 1 && total > options.maxTranscriptChars) {
      total -= _line(segments[drop]).length + 1;
      drop++;
    }
    segments = segments.sublist(drop);
    trimmedBefore = segments.first.start;
  }

  final contextLines = <String>[
    if (input.meetingTitle.trim().isNotEmpty)
      'Meeting title: ${input.meetingTitle.trim()}',
    if (input.globalContext.trim().isNotEmpty)
      'About the user and their projects:\n${input.globalContext.trim()}',
    if (input.meetingContext.trim().isNotEmpty)
      'Context for this meeting:\n${input.meetingContext.trim()}',
    if (input.vocabulary.isNotEmpty)
      'Custom vocabulary (terms that may appear mistranscribed):\n'
          '${input.vocabulary.join(', ')}',
  ];

  final content = <Map<String, dynamic>>[
    {
      'type': 'text',
      'text': contextLines.isEmpty
          ? 'No additional context was provided.'
          : contextLines.join('\n\n'),
    },
  ];

  final blocks = <int, StringBuffer>{};
  for (final s in segments) {
    final index = s.start.inMilliseconds ~/ transcriptBlockSpan.inMilliseconds;
    (blocks[index] ??= StringBuffer()).writeln(_line(s));
  }
  final keys = blocks.keys.toList()..sort();
  for (final (i, key) in keys.indexed) {
    content.add({
      'type': 'text',
      'text': '${i == 0 ? 'Transcript:\n' : ''}${blocks[key]}',
    });
  }
  if (keys.isEmpty) {
    content.add({'type': 'text', 'text': 'Transcript:\n(empty so far)'});
  }
  // Cache breakpoint on the last transcript block: context + transcript is
  // the reusable prefix.
  content.last['cache_control'] = {'type': 'ephemeral'};

  final trimNote = trimmedBefore == null
      ? ''
      : '\n\nNote: the transcript was too long to send in full; it starts at '
            '[${formatHms(trimmedBefore)}] and earlier parts are omitted.';
  content.add({
    'type': 'text',
    'text':
        '${options.retryReminder ? _retryInstruction : _instruction}$trimNote',
  });

  final system = <Map<String, dynamic>>[
    {'type': 'text', 'text': systemPrompt.trim()},
    if (options.checkDocs) {'type': 'text', 'text': docsAddendum.trim()},
  ];
  system.last['cache_control'] = {'type': 'ephemeral'};

  final body = <String, dynamic>{
    'model': options.model,
    'max_tokens': 32000,
    'system': system,
    'messages': [
      {'role': 'user', 'content': content},
    ],
    // Medium effort keeps a typical analysis well under the 30 s target
    // while leaving room to reason about the transcript.
    'output_config': {'effort': 'medium'},
    // Re-run on Anthropic's recommended model if a safety classifier
    // declines (beta header set by the client).
    'fallbacks': 'default',
    if (options.checkDocs && options.docDomains.isNotEmpty)
      'tools': [
        {
          'type': 'web_search_20260209',
          'name': 'web_search',
          'max_uses': options.maxDocLookups,
          'allowed_domains': options.docDomains,
        },
        {
          'type': 'web_fetch_20260209',
          'name': 'web_fetch',
          'max_uses': options.maxDocLookups,
          'allowed_domains': options.docDomains,
        },
      ],
  };

  return BuiltAnalysisRequest(
    body: body,
    transcriptUpTo: segments.isEmpty ? Duration.zero : segments.last.end,
    trimmedBefore: trimmedBefore,
  );
}

String _line(Segment s) => '[${formatHms(s.start)}] ${s.text.trim()}';
