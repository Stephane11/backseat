import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

/// Minimal Anthropic Messages API client over raw HTTP + SSE (there is no
/// official Dart SDK). Never logs request bodies: they contain transcript
/// text.
class ClaudeClient {
  ClaudeClient({required this.apiKey, Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 20),
              // The stream sends `ping` events, so a long silence means a
              // dead connection rather than a slow model.
              receiveTimeout: const Duration(seconds: 90),
            ),
          );

  static const endpoint = 'https://api.anthropic.com/v1/messages';
  static const apiVersion = '2023-06-01';

  /// Server-side refusal fallback (`fallbacks: "default"` in the body).
  static const betas = ['server-side-fallback-2026-07-01'];

  final String apiKey;
  final Dio _dio;

  /// Streams decoded SSE `data:` payloads for one request.
  Stream<Map<String, dynamic>> streamEvents(
    Map<String, dynamic> body, {
    CancelToken? cancelToken,
  }) async* {
    final Response<ResponseBody> response;
    try {
      response = await _dio.post<ResponseBody>(
        endpoint,
        data: jsonEncode({...body, 'stream': true}),
        cancelToken: cancelToken,
        options: Options(
          responseType: ResponseType.stream,
          validateStatus: (_) => true,
          headers: {
            'x-api-key': apiKey,
            'anthropic-version': apiVersion,
            'anthropic-beta': betas.join(','),
            'content-type': 'application/json',
            'accept': 'text/event-stream',
          },
        ),
      );
    } on DioException catch (e) {
      throw _fromDio(e);
    }

    final status = response.statusCode ?? 0;
    final bytes = response.data!.stream;
    if (status != 200) {
      final text = await utf8.decodeStream(bytes).catchError((_) => '');
      throw ClaudeApiException.fromHttp(
        status,
        text,
        retryAfter: int.tryParse(response.headers.value('retry-after') ?? ''),
      );
    }

    try {
      await for (final event in parseSse(bytes.cast<List<int>>())) {
        if (event['type'] == 'error') {
          final error = event['error'] as Map<String, dynamic>? ?? const {};
          throw ClaudeApiException.fromErrorType(
            error['type'] as String? ?? 'api_error',
            error['message'] as String? ?? '',
          );
        }
        yield event;
      }
    } on DioException catch (e) {
      throw _fromDio(e);
    }
  }

  ClaudeApiException _fromDio(DioException e) {
    if (e.type == DioExceptionType.cancel) {
      return const ClaudeApiException(ClaudeErrorKind.cancelled, 'Cancelled.');
    }
    return const ClaudeApiException(
      ClaudeErrorKind.network,
      "Couldn't reach Claude. Check your connection and try again.",
    );
  }
}

/// Splits a byte stream of Server-Sent Events into decoded JSON payloads.
/// Only `data:` lines matter: every payload carries its own `type`.
Stream<Map<String, dynamic>> parseSse(Stream<List<int>> bytes) async* {
  final data = StringBuffer();
  await for (final line
      in bytes.transform(utf8.decoder).transform(const LineSplitter())) {
    if (line.isEmpty) {
      if (data.isNotEmpty) {
        final payload = data.toString();
        data.clear();
        final decoded = jsonDecode(payload);
        if (decoded is Map<String, dynamic>) yield decoded;
      }
    } else if (line.startsWith('data:')) {
      if (data.isNotEmpty) data.write('\n');
      data.write(line.substring(5).trimLeft());
    }
  }
  if (data.isNotEmpty) {
    final decoded = jsonDecode(data.toString());
    if (decoded is Map<String, dynamic>) yield decoded;
  }
}

enum ClaudeErrorKind {
  noApiKey,
  auth,
  permission,
  billing,
  rateLimited,
  overloaded,
  server,
  network,
  badRequest,
  webSearchDisabled,
  refused,
  cancelled,
}

class ClaudeApiException implements Exception {
  const ClaudeApiException(this.kind, this.message, {this.retryAfter});

  factory ClaudeApiException.fromHttp(
    int status,
    String body, {
    int? retryAfter,
  }) {
    var type = 'api_error';
    var message = '';
    try {
      final error =
          (jsonDecode(body) as Map<String, dynamic>)['error']
              as Map<String, dynamic>;
      type = error['type'] as String? ?? type;
      message = error['message'] as String? ?? '';
    } catch (_) {
      // Non-JSON body (proxy error page etc.): classify by status alone.
    }
    if (status == 529) type = 'overloaded_error';
    if (status == 429) type = 'rate_limit_error';
    if (status == 401) type = 'authentication_error';
    return ClaudeApiException.fromErrorType(
      type,
      message,
      retryAfter: retryAfter,
    );
  }

  factory ClaudeApiException.fromErrorType(
    String type,
    String message, {
    int? retryAfter,
  }) {
    final lower = message.toLowerCase();
    final aboutWebTools = RegExp(r'web[ _](search|fetch)').hasMatch(lower);
    final notEnabled = RegExp(
      r'not enabled|disabled|enable it|not available|not allowed',
    ).hasMatch(lower);
    if (aboutWebTools && notEnabled) {
      return const ClaudeApiException(
        ClaudeErrorKind.webSearchDisabled,
        'Web search / fetch is not enabled for your organisation. Enable it in '
        'the Claude Console, or turn off "Check against docs".',
      );
    }
    return switch (type) {
      'authentication_error' => const ClaudeApiException(
        ClaudeErrorKind.auth,
        'Your Claude API key was rejected. Check it in Settings.',
      ),
      'permission_error' => const ClaudeApiException(
        ClaudeErrorKind.permission,
        "Your API key doesn't have access to this model or feature.",
      ),
      'billing_error' => const ClaudeApiException(
        ClaudeErrorKind.billing,
        'Billing issue on your Anthropic account (credits or payment method).',
      ),
      'rate_limit_error' => ClaudeApiException(
        ClaudeErrorKind.rateLimited,
        retryAfter == null
            ? 'Rate limited by the API. Try again in a moment.'
            : 'Rate limited by the API. Try again in ${retryAfter}s.',
        retryAfter: retryAfter,
      ),
      'overloaded_error' => const ClaudeApiException(
        ClaudeErrorKind.overloaded,
        'Claude is temporarily overloaded. Try again shortly.',
      ),
      'invalid_request_error' => ClaudeApiException(
        ClaudeErrorKind.badRequest,
        message.isEmpty ? 'The request was rejected.' : message,
      ),
      _ => const ClaudeApiException(
        ClaudeErrorKind.server,
        'The Claude API had a problem. Try again.',
      ),
    };
  }

  final ClaudeErrorKind kind;
  final String message;
  final int? retryAfter;

  bool get retryable => switch (kind) {
    ClaudeErrorKind.rateLimited ||
    ClaudeErrorKind.overloaded ||
    ClaudeErrorKind.server ||
    ClaudeErrorKind.network ||
    ClaudeErrorKind.refused => true,
    _ => false,
  };

  @override
  String toString() => message;
}

/// Progress callbacks while a response streams in.
sealed class StreamStatus {
  const StreamStatus();
}

class StatusThinking extends StreamStatus {
  const StatusThinking();
}

class StatusSearching extends StreamStatus {
  const StatusSearching(this.query);
  final String query;
}

class StatusReading extends StreamStatus {
  const StatusReading(this.url);
  final String url;
}

class StatusWriting extends StreamStatus {
  const StatusWriting(this.characters);
  final int characters;
}

/// Rebuilds full content blocks from stream events, so a `pause_turn` can be
/// continued by echoing the assistant turn back verbatim (server tool calls,
/// their results and thinking signatures included).
class MessageAccumulator {
  MessageAccumulator({this.onStatus});

  final void Function(StreamStatus status)? onStatus;

  final blocks = <Map<String, dynamic>>[];
  final _partialJson = <int, StringBuffer>{};
  String? model;
  String? stopReason;
  int _textChars = 0;

  void add(Map<String, dynamic> event) {
    switch (event['type']) {
      case 'message_start':
        final message = event['message'] as Map<String, dynamic>;
        model = message['model'] as String?;
      case 'content_block_start':
        final index = event['index'] as int;
        final block = Map<String, dynamic>.from(
          event['content_block'] as Map<String, dynamic>,
        );
        while (blocks.length <= index) {
          blocks.add({});
        }
        blocks[index] = block;
        if (block['type'] == 'thinking') onStatus?.call(const StatusThinking());
      case 'content_block_delta':
        final index = event['index'] as int;
        final delta = event['delta'] as Map<String, dynamic>;
        final block = blocks[index];
        switch (delta['type']) {
          case 'text_delta':
            final text = delta['text'] as String;
            block['text'] = (block['text'] as String? ?? '') + text;
            _textChars += text.length;
            onStatus?.call(StatusWriting(_textChars));
          case 'input_json_delta':
            (_partialJson[index] ??= StringBuffer()).write(
              delta['partial_json'] as String,
            );
          case 'thinking_delta':
            block['thinking'] =
                (block['thinking'] as String? ?? '') +
                (delta['thinking'] as String);
          case 'signature_delta':
            block['signature'] = delta['signature'];
          case 'citations_delta':
            (block['citations'] ??= <dynamic>[]).add(delta['citation']);
        }
      case 'content_block_stop':
        final index = event['index'] as int;
        final block = blocks[index];
        final json = _partialJson.remove(index);
        if (json != null && json.isNotEmpty) {
          try {
            block['input'] = jsonDecode(json.toString());
          } on FormatException {
            block['input'] = <String, dynamic>{};
          }
        }
        if (block['type'] == 'server_tool_use') {
          final input = block['input'] as Map<String, dynamic>? ?? const {};
          if (block['name'] == 'web_search' && input['query'] is String) {
            onStatus?.call(StatusSearching(input['query'] as String));
          } else if (block['name'] == 'web_fetch' && input['url'] is String) {
            onStatus?.call(StatusReading(input['url'] as String));
          }
        }
      case 'message_delta':
        final delta = event['delta'] as Map<String, dynamic>;
        stopReason = delta['stop_reason'] as String? ?? stopReason;
    }
  }

  /// Concatenated text of every text block (a server-side fallback keeps the
  /// declined partial and continues it, and citations split text into
  /// several blocks, so all of them together form the answer).
  String get text => blocks
      .where((b) => b['type'] == 'text')
      .map((b) => b['text'] as String? ?? '')
      .join();

  /// Text written after the last tool call / result: the final answer when
  /// Claude narrated ("Let me check the docs…") before using tools.
  String get tailText {
    final lastOther = blocks.lastIndexWhere(
      (b) => b.isNotEmpty && b['type'] != 'text' && b['type'] != 'fallback',
    );
    return blocks
        .skip(lastOther + 1)
        .where((b) => b['type'] == 'text')
        .map((b) => b['text'] as String? ?? '')
        .join();
  }

  /// The assistant content to echo back when continuing a `pause_turn`.
  /// Before the last `fallback` marker, only text and paired server-tool
  /// blocks are kept (the API's rule for echoing fallback turns).
  List<Map<String, dynamic>> echoContent() {
    final lastFallback = blocks.lastIndexWhere((b) => b['type'] == 'fallback');
    final resultIds = {
      for (final b in blocks)
        if (b['tool_use_id'] != null) b['tool_use_id'],
    };
    return [
      for (final (i, b) in blocks.indexed)
        if (b.isNotEmpty &&
            b['type'] != 'fallback' &&
            (i > lastFallback ||
                b['type'] == 'text' ||
                (b['type'] == 'server_tool_use' &&
                    resultIds.contains(b['id'])) ||
                (b['tool_use_id'] != null)))
          b,
    ];
  }
}
