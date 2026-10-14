import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/models/meeting.dart';
import '../../core/providers/app_providers.dart';
import 'model_download_service.dart';
import 'sherpa_onnx_transcription_engine.dart';
import 'transcription_engine.dart';

typedef TranscriptionEngineBuilder = Future<TranscriptionEngine> Function(
  Meeting meeting,
);

/// Builds the [TranscriptionEngine] a Live meeting screen should use.
/// Overridden in widget tests with a builder that returns
/// `FakeTranscriptionEngine` instead, since the real one drives microphone,
/// ASR and foreground-service platform channels tests can't exercise.
final transcriptionEngineBuilderProvider = Provider<TranscriptionEngineBuilder>(
  (ref) {
    return (meeting) async {
      final downloads = ref.read(modelDownloadServiceProvider);
      if (!await downloads.isReady(AsrModelId.streamingZipformerEn)) {
        throw const TranscriptionStartException(
          'The on-device speech model is not downloaded yet.',
          needsModel: true,
        );
      }
      final settings = ref.read(settingsProvider);
      final docs = await getApplicationDocumentsDirectory();
      return SherpaOnnxTranscriptionEngine(
        modelPaths: await downloads.streamingPaths(),
        wavPath: p.join(docs.path, 'recordings', '${meeting.id}.wav'),
        vocabulary: [...settings.customVocabulary, ...meeting.extraTerms],
        boostStrength: settings.boostStrength,
      );
    };
  },
);
