import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:backseat/features/analysis/claude_client.dart';

Stream<List<int>> chunked(String text, int size) async* {
  final bytes = utf8.encode(text);
  for (var i = 0; i < bytes.length; i += size) {
    yield bytes.sublist(i, (i + size).clamp(0, bytes.length));
  }
}

String sse(List<Map<String, dynamic>> events) =>
    events.map((e) => 'event: ${e['type']}\ndata: ${jsonEncode(e)}\n\n').join();

void main() {
  group('parseSse', () {
    test('decodes events split across arbitrary byte chunks', () async {
      final text = sse([
        {
          'type': 'message_start',
          'message': {'model': 'claude-sonnet-5-5'},
        },
        {'type': 'ping'},
        {
          'type': 'content_block_delta',
          'index': 0,
          'delta': {'type': 'text_delta', 'text': 'héllo – “quotes”'},
        },
      ]);
      for (final size in [1, 3, 7, 64]) {
        final events = await parseSse(chunked(text, size)).toList();
        expect(events.map((e) => e['type']), [
          'message_start',
          'ping',
          'content_block_delta',
        ]);
        expect(events.last['delta']['text'], 'héllo – “quotes”');
      }
    });
  });

  group('MessageAccumulator', () {
    test('rebuilds text, server tool calls and reports status', () {
      final statuses = <StreamStatus>[];
      final acc = MessageAccumulator(onStatus: statuses.add);
      final events = <Map<String, dynamic>>[
        {
          'type': 'message_start',
          'message': {'model': 'claude-opus-5-5'},
        },
        {
          'type': 'content_block_start',
          'index': 0,
          'content_block': {
            'type': 'thinking',
            'thinking': '',
            'signature': '',
          },
        },
        {
          'type': 'content_block_delta',
          'index': 0,
          'delta': {'type': 'signature_delta', 'signature': 'sig'},
        },
        {'type': 'content_block_stop', 'index': 0},
        {
          'type': 'content_block_start',
          'index': 1,
          'content_block': {
            'type': 'server_tool_use',
            'id': 'srvtoolu_1',
            'name': 'web_search',
            'input': {},
          },
        },
        {
          'type': 'content_block_delta',
          'index': 1,
          'delta': {
            'type': 'input_json_delta',
            'partial_json': '{"query": "Unity Catalog',
          },
        },
        {
          'type': 'content_block_delta',
          'index': 1,
          'delta': {'type': 'input_json_delta', 'partial_json': ' grants"}'},
        },
        {'type': 'content_block_stop', 'index': 1},
        {
          'type': 'content_block_start',
          'index': 2,
          'content_block': {
            'type': 'web_search_tool_result',
            'tool_use_id': 'srvtoolu_1',
            'content': [],
          },
        },
        {'type': 'content_block_stop', 'index': 2},
        {
          'type': 'content_block_start',
          'index': 3,
          'content_block': {'type': 'text', 'text': ''},
        },
        {
          'type': 'content_block_delta',
          'index': 3,
          'delta': {'type': 'text_delta', 'text': '{"summary": '},
        },
        {
          'type': 'content_block_delta',
          'index': 3,
          'delta': {'type': 'text_delta', 'text': '"s", "items": []}'},
        },
        {'type': 'content_block_stop', 'index': 3},
        {
          'type': 'message_delta',
          'delta': {'stop_reason': 'end_turn'},
        },
      ];
      events.forEach(acc.add);

      expect(acc.model, 'claude-opus-5-5');
      expect(acc.stopReason, 'end_turn');
      expect(acc.text, '{"summary": "s", "items": []}');
      expect(acc.blocks[0]['signature'], 'sig');
      expect(acc.blocks[1]['input'], {'query': 'Unity Catalog grants'});
      expect(statuses.whereType<StatusThinking>(), isNotEmpty);
      expect(
        statuses.whereType<StatusSearching>().single.query,
        'Unity Catalog grants',
      );
      expect(statuses.last, isA<StatusWriting>());
      // Whole turn is echoed back for a pause_turn continuation.
      expect(acc.echoContent(), hasLength(4));
    });

    test('echo drops pre-fallback thinking and unpaired tool calls', () {
      final acc = MessageAccumulator();
      for (final (i, block) in [
        {'type': 'thinking', 'thinking': '', 'signature': 's'},
        {'type': 'text', 'text': 'partial '},
        {'type': 'server_tool_use', 'id': 'a', 'name': 'web_search'},
        {'type': 'fallback', 'from': {}, 'to': {}},
        {'type': 'text', 'text': 'rest'},
      ].indexed) {
        acc.add({
          'type': 'content_block_start',
          'index': i,
          'content_block': block,
        });
        acc.add({'type': 'content_block_stop', 'index': i});
      }
      expect(acc.echoContent().map((b) => b['type']), ['text', 'text']);
      expect(acc.text, 'partial rest');
    });
  });

  group('ClaudeApiException', () {
    test('maps HTTP errors to friendly kinds', () {
      ClaudeApiException fromHttp(int status, String type, [String msg = '']) =>
          ClaudeApiException.fromHttp(
            status,
            jsonEncode({
              'type': 'error',
              'error': {'type': type, 'message': msg},
            }),
          );
      expect(fromHttp(401, 'authentication_error').kind, ClaudeErrorKind.auth);
      expect(
        fromHttp(429, 'rate_limit_error').kind,
        ClaudeErrorKind.rateLimited,
      );
      expect(
        fromHttp(529, 'overloaded_error').kind,
        ClaudeErrorKind.overloaded,
      );
      expect(fromHttp(500, 'api_error').kind, ClaudeErrorKind.server);
      expect(fromHttp(402, 'billing_error').kind, ClaudeErrorKind.billing);
      expect(
        fromHttp(
          400,
          'invalid_request_error',
          'Web search is not enabled for this organization.',
        ).kind,
        ClaudeErrorKind.webSearchDisabled,
      );
      expect(
        fromHttp(400, 'invalid_request_error', 'max_tokens: too large').kind,
        ClaudeErrorKind.badRequest,
      );
      expect(
        ClaudeApiException.fromHttp(502, '<html>Bad gateway</html>').kind,
        ClaudeErrorKind.server,
      );
    });

    test('rate limit message includes retry-after', () {
      final e = ClaudeApiException.fromHttp(429, '', retryAfter: 12);
      expect(e.message, contains('12s'));
      expect(e.retryable, isTrue);
    });
  });
}
