import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/analysis.dart';
import '../../core/models/meeting.dart';
import '../../core/providers/app_providers.dart';
import 'analysis_parser.dart';
import 'claude_client.dart';
import 'prompt_builder.dart';

/// Result of one Analyse tap.
sealed class AnalysisOutcome {
  const AnalysisOutcome();
}

class AnalysisSucceeded extends AnalysisOutcome {
  const AnalysisSucceeded(this.analysis, {this.trimmedBefore});
  final Analysis analysis;

  /// Set when the oldest part of a very long transcript was left out.
  final Duration? trimmedBefore;
}

/// Claude answered twice but neither answer parsed: show the raw text.
class AnalysisUnparseable extends AnalysisOutcome {
  const AnalysisUnparseable(this.rawText);
  final String rawText;
}

typedef StatusCallback = void Function(StreamStatus status);

abstract class AnalysisService {
  /// Throws [ClaudeApiException] for API/network problems.
  Future<AnalysisOutcome> analyse(
    Meeting meeting, {
    required bool checkDocs,
    StatusCallback? onStatus,
    CancelToken? cancelToken,
  });
}

class ClaudeAnalysisService implements AnalysisService {
  ClaudeAnalysisService(
    this.ref, {
    ClaudeClient Function(String apiKey)? client,
  }) : _clientFactory = client ?? ((key) => ClaudeClient(apiKey: key));

  final Ref ref;
  final ClaudeClient Function(String apiKey) _clientFactory;
  String? _systemPrompt;
  String? _docsAddendum;

  static const _maxContinuations = 4;

  @override
  Future<AnalysisOutcome> analyse(
    Meeting meeting, {
    required bool checkDocs,
    StatusCallback? onStatus,
    CancelToken? cancelToken,
  }) async {
    final apiKey = await ref.read(apiKeyStoreProvider).read();
    if (apiKey == null || apiKey.isEmpty) {
      throw const ClaudeApiException(
        ClaudeErrorKind.noApiKey,
        'Add your Claude API key in Settings to analyse meetings.',
      );
    }
    _systemPrompt ??= await rootBundle.loadString(
      'assets/prompts/analysis_system.md',
    );
    _docsAddendum ??= await rootBundle.loadString(
      'assets/prompts/analysis_docs.md',
    );

    final settings = ref.read(settingsProvider);
    final client = _clientFactory(apiKey);
    final input = AnalysisInput(
      segments: meeting.finalSegments,
      meetingTitle: meeting.title,
      meetingContext: meeting.contextNote ?? '',
      globalContext: settings.globalContextNote,
      vocabulary: [...settings.customVocabulary, ...meeting.extraTerms],
    );

    for (final retry in [false, true]) {
      final request = buildAnalysisRequest(
        systemPrompt: _systemPrompt!,
        docsAddendum: _docsAddendum!,
        input: input,
        options: AnalysisRequestOptions(
          model: settings.analysisModel,
          checkDocs: checkDocs,
          docDomains: settings.docDomains,
          maxDocLookups: settings.maxDocLookups,
          retryReminder: retry,
        ),
      );
      final (text, tail, model) = await _runTurn(
        client,
        request.body,
        onStatus: onStatus,
        cancelToken: cancelToken,
      );
      final parsed = parseAnalysisJson(text) ?? parseAnalysisJson(tail);
      if (parsed != null) {
        return AnalysisSucceeded(
          Analysis(
            id: 'analysis-${DateTime.now().microsecondsSinceEpoch}',
            createdAt: DateTime.now(),
            model: model ?? settings.analysisModel,
            transcriptUpTo: request.transcriptUpTo,
            summary: parsed.summary,
            items: parsed.items,
          ),
          trimmedBefore: request.trimmedBefore,
        );
      }
      if (retry) return AnalysisUnparseable(text);
    }
    throw StateError('unreachable');
  }

  /// One assistant turn, following `pause_turn` continuations of the
  /// server-side tool loop. Returns all answer text, the text after the
  /// last tool use, and the model that actually produced it (differs after
  /// a refusal fallback).
  Future<(String, String, String?)> _runTurn(
    ClaudeClient client,
    Map<String, dynamic> body, {
    StatusCallback? onStatus,
    CancelToken? cancelToken,
  }) async {
    final userMessage = (body['messages'] as List).first;
    final assistantContent = <Map<String, dynamic>>[];
    final text = StringBuffer();
    var tail = '';
    String? model;

    for (var i = 0; i <= _maxContinuations; i++) {
      final acc = MessageAccumulator(onStatus: onStatus);
      final requestBody = {
        ...body,
        'messages': [
          userMessage,
          if (assistantContent.isNotEmpty)
            {'role': 'assistant', 'content': assistantContent},
        ],
      };
      await for (final event in client.streamEvents(
        requestBody,
        cancelToken: cancelToken,
      )) {
        acc.add(event);
      }
      model = acc.model ?? model;

      if (acc.stopReason == 'refusal') {
        throw const ClaudeApiException(
          ClaudeErrorKind.refused,
          'Claude declined to analyse this transcript. Try again, or switch '
          'models in Settings.',
        );
      }
      text.write(acc.text);
      tail = acc.tailText;
      if (acc.stopReason != 'pause_turn') break;
      assistantContent.addAll(acc.echoContent());
    }
    return (text.toString(), tail, model);
  }
}

/// Overridden in widget tests with a fake that returns canned results.
final analysisServiceProvider = Provider<AnalysisService>(
  (ref) => ClaudeAnalysisService(ref),
);
