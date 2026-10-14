import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:backseat/core/models/meeting.dart';
import 'package:backseat/core/models/segment.dart';
import 'package:backseat/core/models/settings_state.dart';
import 'package:backseat/core/providers/app_providers.dart';
import 'package:backseat/core/storage/api_key_store.dart';
import 'package:backseat/features/analysis/analysis_service.dart';
import 'package:backseat/features/analysis/claude_client.dart';

/// Replays canned HTTP responses and records each request body.
class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.responses);

  final List<ResponseBody Function()> responses;
  final requests = <Map<String, dynamic>>[];
  final headers = <Map<String, dynamic>>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(jsonDecode(options.data as String) as Map<String, dynamic>);
    headers.add(options.headers);
    return responses[requests.length - 1]();
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody sseResponse(List<Map<String, dynamic>> events) {
  final text = events
      .map((e) => 'event: ${e['type']}\ndata: ${jsonEncode(e)}\n\n')
      .join();
  return ResponseBody.fromString(
    text,
    200,
    headers: {
      'content-type': ['text/event-stream'],
    },
  );
}

List<Map<String, dynamic>> textMessage(
  String text, {
  String stopReason = 'end_turn',
  List<Map<String, dynamic>> leadingBlocks = const [],
}) => [
  {
    'type': 'message_start',
    'message': {'model': 'claude-sonnet-5-5'},
  },
  for (final (i, block) in leadingBlocks.indexed) ...[
    {'type': 'content_block_start', 'index': i, 'content_block': block},
    {'type': 'content_block_stop', 'index': i},
  ],
  {
    'type': 'content_block_start',
    'index': leadingBlocks.length,
    'content_block': {'type': 'text', 'text': ''},
  },
  {
    'type': 'content_block_delta',
    'index': leadingBlocks.length,
    'delta': {'type': 'text_delta', 'text': text},
  },
  {'type': 'content_block_stop', 'index': leadingBlocks.length},
  {
    'type': 'message_delta',
    'delta': {'stop_reason': stopReason},
  },
  {'type': 'message_stop'},
];

const validJson =
    '{"summary": "Churn review.", "items": [{"type": "issue", '
    '"category": "statistics", "severity": "high", "title": "Leakage", '
    '"detail": "Use a time split.", "evidence": "random split", '
    '"timestamp": "00:00:05", "sources": []}]}';

final meeting = Meeting(
  id: 'm1',
  title: 'Churn review',
  startedAt: DateTime(2026, 10, 14),
  endedAt: DateTime(2026, 10, 14, 0, 30),
  segments: const [
    Segment(
      id: 'm1_0',
      start: Duration(seconds: 5),
      end: Duration(seconds: 9),
      text: 'the holdout is a random split',
      isFinal: true,
    ),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  (AnalysisService, FakeAdapter) build(
    List<ResponseBody Function()> responses, {
    String? apiKey = 'sk-ant-test',
    String workspaceId = '',
  }) {
    final adapter = FakeAdapter(responses);
    final container = ProviderContainer(
      overrides: [
        apiKeyStoreProvider.overrideWithValue(InMemoryApiKeyStore(apiKey)),
        initialPrefsProvider.overrideWithValue(
          StoredPrefs(settings: SettingsState(workspaceId: workspaceId)),
        ),
        analysisServiceProvider.overrideWith(
          (ref) => ClaudeAnalysisService(
            ref,
            client: (key, workspace) => ClaudeClient(
              apiKey: key,
              workspaceId: workspace,
              dio: Dio()..httpClientAdapter = adapter,
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    return (container.read(analysisServiceProvider), adapter);
  }

  test('streams, parses and returns an analysis', () async {
    final (service, adapter) = build([
      () => sseResponse(textMessage(validJson)),
    ]);
    final outcome = await service.analyse(meeting, checkDocs: false);

    expect(outcome, isA<AnalysisSucceeded>());
    final analysis = (outcome as AnalysisSucceeded).analysis;
    expect(analysis.summary, 'Churn review.');
    expect(analysis.items.single.timestamp, const Duration(seconds: 5));
    expect(analysis.transcriptUpTo, const Duration(seconds: 9));

    final body = adapter.requests.single;
    expect(body['stream'], isTrue);
    expect(body['model'], 'claude-sonnet-5-5');
    expect(body.containsKey('tools'), isFalse);
    expect(adapter.headers.single['x-api-key'], 'sk-ant-test');
    expect(adapter.headers.single['anthropic-version'], '2023-06-01');
    expect(
      adapter.headers.single['anthropic-beta'],
      'server-side-fallback-2026-07-01',
    );
  });

  test('sends anthropic-workspace-id only when a workspace is set', () async {
    final (plain, plainAdapter) = build([
      () => sseResponse(textMessage(validJson)),
    ]);
    await plain.analyse(meeting, checkDocs: false);
    expect(
      plainAdapter.headers.single.containsKey('anthropic-workspace-id'),
      isFalse,
    );

    final (scoped, scopedAdapter) = build([
      () => sseResponse(textMessage(validJson)),
    ], workspaceId: 'wrkspc_01abc');
    await scoped.analyse(meeting, checkDocs: false);
    expect(
      scopedAdapter.headers.single['anthropic-workspace-id'],
      'wrkspc_01abc',
    );
  });

  test(
    'a missing-workspace error points to the Workspace ID setting',
    () async {
      final (service, _) = build([
        () => ResponseBody.fromString(
          jsonEncode({
            'type': 'error',
            'error': {
              'type': 'invalid_request_error',
              'message':
                  'The API key is not scoped to a workspace, so this request '
                  'must include the anthropic-workspace-id header.',
            },
          }),
          400,
        ),
      ]);
      expect(
        () => service.analyse(meeting, checkDocs: false),
        throwsA(
          isA<ClaudeApiException>().having(
            (e) => e.kind,
            'kind',
            ClaudeErrorKind.workspaceRequired,
          ),
        ),
      );
    },
  );

  test('continues a pause_turn by echoing the server tool turn', () async {
    final (service, adapter) = build([
      () => sseResponse(
        textMessage(
          'Let me check the docs. ',
          stopReason: 'pause_turn',
          leadingBlocks: [
            {
              'type': 'server_tool_use',
              'id': 'srvtoolu_1',
              'name': 'web_search',
              'input': {'query': 'auto loader'},
            },
            {
              'type': 'web_search_tool_result',
              'tool_use_id': 'srvtoolu_1',
              'content': [],
            },
          ],
        ),
      ),
      () => sseResponse(textMessage(validJson)),
    ]);
    final statuses = <StreamStatus>[];
    final outcome = await service.analyse(
      meeting,
      checkDocs: true,
      onStatus: statuses.add,
    );

    expect(outcome, isA<AnalysisSucceeded>());
    expect(adapter.requests, hasLength(2));
    expect(adapter.requests.first['tools'], hasLength(2));
    final continued = adapter.requests[1]['messages'] as List;
    expect(continued, hasLength(2));
    expect(continued[1]['role'], 'assistant');
    expect((continued[1]['content'] as List).map((b) => b['type']), [
      'server_tool_use',
      'web_search_tool_result',
      'text',
    ]);
  });

  test('retries once with a JSON reminder, then returns raw text', () async {
    final (service, adapter) = build([
      () => sseResponse(textMessage('Here are my thoughts in prose.')),
      () => sseResponse(textMessage('Still prose, sorry.')),
    ]);
    final outcome = await service.analyse(meeting, checkDocs: false);

    expect(outcome, isA<AnalysisUnparseable>());
    expect((outcome as AnalysisUnparseable).rawText, 'Still prose, sorry.');
    final retryContent =
        (adapter.requests[1]['messages'] as List).single['content'] as List;
    expect(retryContent.last['text'], contains('ONLY the JSON object'));
  });

  test('a refusal surfaces as a friendly error', () async {
    final (service, _) = build([
      () => sseResponse(textMessage('', stopReason: 'refusal')),
    ]);
    expect(
      () => service.analyse(meeting, checkDocs: false),
      throwsA(
        isA<ClaudeApiException>().having(
          (e) => e.kind,
          'kind',
          ClaudeErrorKind.refused,
        ),
      ),
    );
  });

  test('HTTP 401 maps to an auth error', () async {
    final (service, _) = build([
      () => ResponseBody.fromString(
        jsonEncode({
          'type': 'error',
          'error': {
            'type': 'authentication_error',
            'message': 'invalid x-api-key',
          },
        }),
        401,
      ),
    ]);
    expect(
      () => service.analyse(meeting, checkDocs: false),
      throwsA(
        isA<ClaudeApiException>().having(
          (e) => e.kind,
          'kind',
          ClaudeErrorKind.auth,
        ),
      ),
    );
  });

  test('no API key fails fast without a request', () async {
    final (service, adapter) = build([], apiKey: null);
    await expectLater(
      service.analyse(meeting, checkDocs: false),
      throwsA(
        isA<ClaudeApiException>().having(
          (e) => e.kind,
          'kind',
          ClaudeErrorKind.noApiKey,
        ),
      ),
    );
    expect(adapter.requests, isEmpty);
  });
}
