import 'dart:async';
import 'dart:isolate';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../../core/models/segment.dart';
import 'asr_text.dart';
import 'audio_recorder.dart';
import 'model_download_service.dart';
import 'transcription_engine.dart';
import 'wav_file_writer.dart';

/// Real on-device streaming ASR: sherpa-onnx Zipformer transducer fed from
/// the microphone via [AppAudioRecorder]. Decoding runs in a background
/// isolate (brief §7: never on the UI thread); the main isolate only captures
/// audio, writes the WAV and forwards PCM chunks.
///
/// One utterance = one segment id, re-emitted with growing text until the
/// endpointer fires, then locked in as final. Custom vocabulary is passed as
/// per-stream hotwords with modified beam search (brief §3).
class SherpaOnnxTranscriptionEngine implements TranscriptionEngine {
  SherpaOnnxTranscriptionEngine({
    required this.modelPaths,
    required this.wavPath,
    required this.vocabulary,
    required this.boostStrength,
  });

  final StreamingModelPaths modelPaths;
  final String wavPath;
  final List<String> vocabulary;
  final double boostStrength;

  final _audioRecorder = AppAudioRecorder();
  final _segmentsController = StreamController<Segment>.broadcast();
  final _levelController = StreamController<double>.broadcast();

  Isolate? _isolate;
  ReceivePort? _fromWorker;
  SendPort? _toWorker;
  StreamSubscription<RecordedAudio>? _audioSub;
  Completer<void>? _finished;
  bool _started = false;

  @override
  Stream<Segment> get segments => _segmentsController.stream;

  @override
  Stream<double> get audioLevel => _levelController.stream;

  @override
  String? get audioPath => wavPath;

  @override
  Future<void> start() async {
    if (!await _audioRecorder.hasPermission()) {
      throw const TranscriptionStartException(
        'Microphone access is off. Allow it in system settings to record.',
      );
    }

    final fromWorker = ReceivePort();
    _fromWorker = fromWorker;
    final ready = Completer<void>();

    fromWorker.listen((message) {
      if (message is SendPort) {
        _toWorker = message;
      } else if (message is Map) {
        switch (message['t']) {
          case 'ready':
            if (!ready.isCompleted) ready.complete();
          case 'error':
            if (!ready.isCompleted) {
              ready.completeError(
                TranscriptionStartException(
                  'The speech model could not be loaded. Re-download it in '
                  'Settings. (${message['msg']})',
                  needsModel: true,
                ),
              );
            }
          case 'seg':
            _emit(message);
          case 'done':
            _finished?.complete();
        }
      }
    });

    final hotwords = boostStrength > 0 ? formatHotwords(vocabulary) : '';
    _isolate = await Isolate.spawn(
      _asrWorkerMain,
      _WorkerInit(
        replyTo: fromWorker.sendPort,
        encoder: modelPaths.encoder,
        decoder: modelPaths.decoder,
        joiner: modelPaths.joiner,
        tokens: modelPaths.tokens,
        bpeVocab: modelPaths.bpeVocab,
        hotwords: hotwords,
        hotwordsScore: boostStrength,
      ),
      debugName: 'asr-worker',
    );
    await ready.future;

    _audioSub = _audioRecorder.audioStream.listen((chunk) {
      _levelController.add(chunk.level);
      _toWorker?.send(TransferableTypedData.fromList([chunk.pcm16]));
    });
    await _audioRecorder.start(wavFilePath: wavPath);
    _started = true;
  }

  void _emit(Map<dynamic, dynamic> m) {
    if (_segmentsController.isClosed) return;
    _segmentsController.add(
      Segment(
        id: 'seg-${m['id']}',
        start: Duration(milliseconds: m['start'] as int),
        end: Duration(milliseconds: m['end'] as int),
        text: normalizeLiveText(m['text'] as String, vocabulary),
        isFinal: m['final'] as bool,
      ),
    );
  }

  @override
  Future<void> stop() async {
    if (!_started) return;
    _started = false;
    await _audioSub?.cancel();
    _audioSub = null;
    await _audioRecorder.stop();

    // Let the worker flush the last utterance before tearing it down.
    final finished = _finished = Completer<void>();
    _toWorker?.send('finish');
    await finished.future.timeout(const Duration(seconds: 5), onTimeout: () {});
  }

  @override
  Future<void> dispose() async {
    if (_started) await stop();
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _fromWorker?.close();
    await _audioRecorder.dispose();
    await _segmentsController.close();
    await _levelController.close();
  }
}

class _WorkerInit {
  const _WorkerInit({
    required this.replyTo,
    required this.encoder,
    required this.decoder,
    required this.joiner,
    required this.tokens,
    required this.bpeVocab,
    required this.hotwords,
    required this.hotwordsScore,
  });

  final SendPort replyTo;
  final String encoder;
  final String decoder;
  final String joiner;
  final String tokens;
  final String bpeVocab;
  final String hotwords;
  final double hotwordsScore;
}

sherpa.OnlineRecognizer _createRecognizer(
  _WorkerInit init, {
  required bool withHotwords,
}) {
  return sherpa.OnlineRecognizer(
    sherpa.OnlineRecognizerConfig(
      model: sherpa.OnlineModelConfig(
        transducer: sherpa.OnlineTransducerModelConfig(
          encoder: init.encoder,
          decoder: init.decoder,
          joiner: init.joiner,
        ),
        tokens: init.tokens,
        modelType: 'zipformer',
        numThreads: 2,
        debug: false,
        modelingUnit: withHotwords ? 'bpe' : '',
        bpeVocab: withHotwords ? init.bpeVocab : '',
      ),
      // Hotwords only take effect with beam search.
      decodingMethod: withHotwords ? 'modified_beam_search' : 'greedy_search',
      hotwordsScore: init.hotwordsScore,
    ),
  );
}

/// Worker isolate entry point. Owns the recognizer; receives PCM16 chunks as
/// [TransferableTypedData] and `'finish'`; replies with segment maps.
/// Timestamps come from the count of samples fed, so they line up exactly
/// with byte offsets in the WAV (used by the Whisper final pass).
void _asrWorkerMain(_WorkerInit init) {
  final inbox = ReceivePort();
  final out = init.replyTo;
  out.send(inbox.sendPort);

  sherpa.OnlineRecognizer recognizer;
  sherpa.OnlineStream stream;
  try {
    sherpa.initBindings();
    final wantHotwords = init.hotwords.isNotEmpty;
    try {
      recognizer = _createRecognizer(init, withHotwords: wantHotwords);
      stream = wantHotwords
          ? recognizer.createStream(hotwords: init.hotwords)
          : recognizer.createStream();
    } catch (_) {
      if (!wantHotwords) rethrow;
      // Vocabulary biasing is a nice-to-have; never let it block recording.
      recognizer = _createRecognizer(init, withHotwords: false);
      stream = recognizer.createStream();
    }
  } catch (e) {
    out.send({'t': 'error', 'msg': e.toString()});
    inbox.close();
    return;
  }
  out.send({'t': 'ready'});

  var samplesFed = 0;
  var utterance = 0;
  int? utteranceStartMs;
  var lastText = '';

  int nowMs() => samplesFed ~/ (AppAudioRecorder.sampleRate ~/ 1000);

  void decodeAvailable() {
    while (recognizer.isReady(stream)) {
      recognizer.decode(stream);
    }
  }

  void sendSegment(String text, {required bool isFinal}) {
    out.send({
      't': 'seg',
      'id': utterance,
      'start': utteranceStartMs ?? nowMs(),
      'end': nowMs(),
      'text': text,
      'final': isFinal,
    });
  }

  void finalizeUtterance(String text) {
    if (text.isNotEmpty) {
      sendSegment(text, isFinal: true);
      utterance++;
    }
    utteranceStartMs = null;
    lastText = '';
  }

  inbox.listen((message) {
    if (message is TransferableTypedData) {
      final samples = pcm16ToFloat32(message.materialize().asUint8List());
      stream.acceptWaveform(
        samples: samples,
        sampleRate: AppAudioRecorder.sampleRate,
      );
      decodeAvailable();
      final startOfChunkMs = nowMs();
      samplesFed += samples.length;

      final text = recognizer.getResult(stream).text.trim();
      if (text.isNotEmpty && text != lastText) {
        utteranceStartMs ??= startOfChunkMs;
        lastText = text;
        sendSegment(text, isFinal: false);
      }
      if (recognizer.isEndpoint(stream)) {
        finalizeUtterance(text);
        recognizer.reset(stream);
      }
    } else if (message == 'finish') {
      stream.inputFinished();
      decodeAvailable();
      finalizeUtterance(recognizer.getResult(stream).text.trim());
      stream.free();
      recognizer.free();
      out.send({'t': 'done'});
      inbox.close();
    }
  });
}
