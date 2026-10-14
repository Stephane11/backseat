import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/models/settings_state.dart';

enum AsrModelId { streamingZipformerEn, whisperSmallEn, whisperBaseEn }

/// One downloadable on-device model. Files come straight from the
/// sherpa-onnx author's Hugging Face model repos (the same artifacts the
/// k2-fsa/sherpa-onnx GitHub release archives package), fetched file by file
/// so only the int8 weights are downloaded and nothing has to be unpacked.
class AsrModelSpec {
  const AsrModelSpec({
    required this.id,
    required this.displayName,
    required this.repo,
    required this.files,
  });

  final AsrModelId id;
  final String displayName;
  final String repo;

  /// Remote file name -> expected size in bytes (for overall progress).
  final Map<String, int> files;

  int get totalBytes => files.values.fold(0, (a, b) => a + b);

  String get sizeLabel => '${(totalBytes / 1e6).round()} MB';

  Uri urlFor(String file) =>
      Uri.parse('https://huggingface.co/csukuangfj/$repo/resolve/main/$file');
}

const kAsrModels = {
  AsrModelId.streamingZipformerEn: AsrModelSpec(
    id: AsrModelId.streamingZipformerEn,
    displayName: 'Zipformer streaming (English)',
    repo: 'sherpa-onnx-streaming-zipformer-en-2023-06-21',
    files: {
      'encoder-epoch-99-avg-1.int8.onnx': 187823992,
      'decoder-epoch-99-avg-1.int8.onnx': 539246,
      'joiner-epoch-99-avg-1.int8.onnx': 259335,
      'tokens.txt': 5048,
    },
  ),
  AsrModelId.whisperSmallEn: AsrModelSpec(
    id: AsrModelId.whisperSmallEn,
    displayName: 'Whisper small.en',
    repo: 'sherpa-onnx-whisper-small.en',
    files: {
      'small.en-encoder.int8.onnx': 112442483,
      'small.en-decoder.int8.onnx': 262223042,
      'small.en-tokens.txt': 835554,
    },
  ),
  AsrModelId.whisperBaseEn: AsrModelSpec(
    id: AsrModelId.whisperBaseEn,
    displayName: 'Whisper base.en',
    repo: 'sherpa-onnx-whisper-base.en',
    files: {
      'base.en-encoder.int8.onnx': 29120534,
      'base.en-decoder.int8.onnx': 130669978,
      'base.en-tokens.txt': 835554,
    },
  ),
};

AsrModelId? finalPassModelId(FinalPassModel model) => switch (model) {
  FinalPassModel.whisperSmallEn => AsrModelId.whisperSmallEn,
  FinalPassModel.whisperBaseEn => AsrModelId.whisperBaseEn,
  FinalPassModel.off => null,
};

class StreamingModelPaths {
  const StreamingModelPaths({
    required this.encoder,
    required this.decoder,
    required this.joiner,
    required this.tokens,
    required this.bpeVocab,
  });

  final String encoder;
  final String decoder;
  final String joiner;
  final String tokens;

  /// Generated from tokens.txt after download (see [_writeBpeVocab]); needed
  /// for hotword (custom vocabulary) encoding.
  final String bpeVocab;
}

class WhisperModelPaths {
  const WhisperModelPaths({
    required this.encoder,
    required this.decoder,
    required this.tokens,
  });

  final String encoder;
  final String decoder;
  final String tokens;
}

class ModelDownloadService {
  Future<Directory> _dirFor(AsrModelSpec spec) async {
    final support = await getApplicationSupportDirectory();
    return Directory(p.join(support.path, 'models', spec.repo));
  }

  Future<String> _path(AsrModelSpec spec, String file) async =>
      p.join((await _dirFor(spec)).path, file);

  Future<StreamingModelPaths> streamingPaths() async {
    final spec = kAsrModels[AsrModelId.streamingZipformerEn]!;
    final names = spec.files.keys.toList();
    return StreamingModelPaths(
      encoder: await _path(spec, names[0]),
      decoder: await _path(spec, names[1]),
      joiner: await _path(spec, names[2]),
      tokens: await _path(spec, names[3]),
      bpeVocab: await _path(spec, 'bpe.vocab'),
    );
  }

  Future<WhisperModelPaths> whisperPaths(AsrModelId id) async {
    final spec = kAsrModels[id]!;
    final names = spec.files.keys.toList();
    return WhisperModelPaths(
      encoder: await _path(spec, names[0]),
      decoder: await _path(spec, names[1]),
      tokens: await _path(spec, names[2]),
    );
  }

  Future<bool> isReady(AsrModelId id) async {
    final spec = kAsrModels[id]!;
    for (final name in spec.files.keys) {
      if (!await File(await _path(spec, name)).exists()) return false;
    }
    if (id == AsrModelId.streamingZipformerEn) {
      return File(await _path(spec, 'bpe.vocab')).exists();
    }
    return true;
  }

  /// Downloads every missing file to `<name>.part` and renames on success,
  /// so an interrupted download never leaves a truncated model that looks
  /// complete. [onProgress] reports 0.0-1.0 across all files.
  Future<void> download(
    AsrModelId id, {
    required void Function(double progress) onProgress,
    CancelToken? cancelToken,
  }) async {
    final spec = kAsrModels[id]!;
    final dir = await _dirFor(spec);
    await dir.create(recursive: true);
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 60),
      ),
    );

    var doneBytes = 0;
    for (final entry in spec.files.entries) {
      final target = File(p.join(dir.path, entry.key));
      if (await target.exists()) {
        doneBytes += entry.value;
        onProgress(doneBytes / spec.totalBytes);
        continue;
      }
      final part = '${target.path}.part';
      await dio.download(
        spec.urlFor(entry.key).toString(),
        part,
        cancelToken: cancelToken,
        deleteOnError: true,
        onReceiveProgress: (received, _) =>
            onProgress(((doneBytes + received) / spec.totalBytes).clamp(0, 1)),
      );
      await File(part).rename(target.path);
      doneBytes += entry.value;
    }

    if (id == AsrModelId.streamingZipformerEn) {
      final paths = await streamingPaths();
      await _writeBpeVocab(paths.tokens, paths.bpeVocab);
    }
    onProgress(1);
  }

  /// sherpa-onnx encodes hotwords with a SentencePiece-style vocab
  /// (`piece<TAB>score`), which this model's repo doesn't ship. Its
  /// tokens.txt lists BPE pieces in SentencePiece id order, and SentencePiece
  /// BPE ids are ordered by merge score, so `-id` reproduces the ranking.
  Future<void> _writeBpeVocab(String tokensPath, String vocabPath) async {
    final lines = await File(tokensPath).readAsLines();
    final buffer = StringBuffer();
    for (final line in lines) {
      final sep = line.lastIndexOf(' ');
      if (sep <= 0) continue;
      final piece = line.substring(0, sep);
      final id = int.tryParse(line.substring(sep + 1));
      if (id == null) continue;
      final special = piece.startsWith('<') && piece.endsWith('>');
      buffer.writeln('$piece\t${special ? 0 : -id}');
    }
    await File(vocabPath).writeAsString(buffer.toString());
  }

  Future<void> delete(AsrModelId id) async {
    final dir = await _dirFor(kAsrModels[id]!);
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}

/// Overridden in widget tests with a stub that completes instantly instead
/// of downloading hundreds of MB over the network.
final modelDownloadServiceProvider = Provider<ModelDownloadService>(
  (ref) => ModelDownloadService(),
);

enum ModelStatus { unknown, missing, downloading, ready, error }

class ModelDownloadState {
  const ModelDownloadState(this.status, {this.progress = 0, this.error});

  final ModelStatus status;
  final double progress;
  final String? error;
}

/// App-wide download state per model, so a download started in onboarding or
/// Settings keeps its progress visible wherever the user navigates.
class ModelDownloadsNotifier
    extends Notifier<Map<AsrModelId, ModelDownloadState>> {
  final _inFlight = <AsrModelId, Future<void>>{};

  @override
  Map<AsrModelId, ModelDownloadState> build() {
    unawaited(refresh());
    return {
      for (final id in AsrModelId.values)
        id: const ModelDownloadState(ModelStatus.unknown),
    };
  }

  ModelDownloadService get _service => ref.read(modelDownloadServiceProvider);

  void _set(AsrModelId id, ModelDownloadState s) => state = {...state, id: s};

  Future<void> refresh() async {
    for (final id in AsrModelId.values) {
      if (_inFlight.containsKey(id)) continue;
      final ready = await _service.isReady(id);
      _set(
        id,
        ModelDownloadState(ready ? ModelStatus.ready : ModelStatus.missing),
      );
    }
  }

  /// Idempotent: a second call while a download runs returns the same future.
  Future<void> download(AsrModelId id) {
    return _inFlight[id] ??= _run(id).whenComplete(() => _inFlight.remove(id));
  }

  Future<void> _run(AsrModelId id) async {
    _set(id, const ModelDownloadState(ModelStatus.downloading));
    var lastReported = -1.0;
    try {
      await _service.download(
        id,
        onProgress: (progress) {
          // Throttle rebuilds to whole-percent steps.
          if (progress - lastReported < 0.01 && progress < 1) return;
          lastReported = progress;
          _set(
            id,
            ModelDownloadState(ModelStatus.downloading, progress: progress),
          );
        },
      );
      _set(id, const ModelDownloadState(ModelStatus.ready, progress: 1));
    } catch (e) {
      _set(
        id,
        const ModelDownloadState(
          ModelStatus.error,
          error: "Download failed. Check your connection and retry.",
        ),
      );
    }
  }

  Future<void> delete(AsrModelId id) async {
    await _service.delete(id);
    _set(id, const ModelDownloadState(ModelStatus.missing));
  }
}

final modelDownloadsProvider =
    NotifierProvider<
      ModelDownloadsNotifier,
      Map<AsrModelId, ModelDownloadState>
    >(ModelDownloadsNotifier.new);
