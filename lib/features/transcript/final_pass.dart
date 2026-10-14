import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../../core/models/meeting.dart';
import '../../core/models/segment.dart';
import '../../core/models/settings_state.dart';
import '../../core/providers/app_providers.dart';
import '../recording/model_download_service.dart';
import '../recording/recording_foreground_service.dart';
import '../recording/wav_file_writer.dart';

/// A window of the saved recording to re-transcribe with Whisper, built from
/// consecutive live segments so it stays under Whisper's 30 s input limit
/// and skips the silences the live endpointer already found.
class FinalPassChunk {
  const FinalPassChunk({
    required this.start,
    required this.end,
    required this.liveText,
  });

  final Duration start;
  final Duration end;

  /// Kept as a fallback if Whisper returns nothing for this window.
  final String liveText;
}

const _maxChunkSpan = Duration(seconds: 25);
const _maxGap = Duration(seconds: 3);
const _padding = Duration(milliseconds: 250);

List<FinalPassChunk> planFinalPassChunks(List<Segment> liveSegments) {
  final segments = liveSegments.where((s) => s.isFinal).toList()
    ..sort((a, b) => a.start.compareTo(b.start));
  final chunks = <FinalPassChunk>[];
  Segment? first;
  Segment? last;
  final texts = <String>[];

  void flush() {
    if (first == null || last == null) return;
    final start = first!.start - _padding;
    chunks.add(
      FinalPassChunk(
        start: start.isNegative ? Duration.zero : start,
        end: last!.end + _padding,
        liveText: texts.join(' '),
      ),
    );
    texts.clear();
    first = null;
    last = null;
  }

  for (final seg in segments) {
    if (first != null &&
        (seg.end - first!.start > _maxChunkSpan ||
            seg.start - last!.end > _maxGap)) {
      flush();
    }
    first ??= seg;
    last = seg;
    texts.add(seg.text);
  }
  flush();
  return chunks;
}

/// Runs Whisper over [chunks] of the WAV at [wavPath] in a background
/// isolate. [onProgress] gets 0.0-1.0; returns the replacement segments.
Future<List<Segment>> transcribeWithWhisper({
  required String meetingId,
  required String wavPath,
  required WhisperModelPaths model,
  required List<FinalPassChunk> chunks,
  required void Function(double progress) onProgress,
}) async {
  final fromWorker = ReceivePort();
  final done = Completer<List<String>>();
  fromWorker.listen((message) {
    if (message is double) {
      onProgress(message);
    } else if (message is List) {
      done.complete(message.cast<String>());
    } else if (message is String) {
      done.completeError(Exception(message));
    }
  });

  final isolate = await Isolate.spawn(
    _finalPassWorkerMain,
    _FinalPassInit(
      replyTo: fromWorker.sendPort,
      wavPath: wavPath,
      encoder: model.encoder,
      decoder: model.decoder,
      tokens: model.tokens,
      startsMs: [for (final c in chunks) c.start.inMilliseconds],
      endsMs: [for (final c in chunks) c.end.inMilliseconds],
    ),
    debugName: 'final-pass-worker',
  );

  try {
    final texts = await done.future;
    return [
      for (var i = 0; i < chunks.length; i++)
        if ((texts[i].isNotEmpty ? texts[i] : chunks[i].liveText).isNotEmpty)
          Segment(
            id: '${meetingId}_final_$i',
            start: chunks[i].start,
            end: chunks[i].end,
            text: texts[i].isNotEmpty ? texts[i] : chunks[i].liveText,
            isFinal: true,
          ),
    ];
  } finally {
    fromWorker.close();
    isolate.kill();
  }
}

class _FinalPassInit {
  const _FinalPassInit({
    required this.replyTo,
    required this.wavPath,
    required this.encoder,
    required this.decoder,
    required this.tokens,
    required this.startsMs,
    required this.endsMs,
  });

  final SendPort replyTo;
  final String wavPath;
  final String encoder;
  final String decoder;
  final String tokens;
  final List<int> startsMs;
  final List<int> endsMs;
}

const _bytesPerMs = 16000 * 2 ~/ 1000;

/// Reads each window straight from the file by byte offset (the WAV may be
/// hours long, so it is never loaded whole), and tolerates a header whose
/// size fields were never patched because recording was interrupted.
Future<void> _finalPassWorkerMain(_FinalPassInit init) async {
  final out = init.replyTo;
  RandomAccessFile? raf;
  sherpa.OfflineRecognizer? recognizer;
  try {
    sherpa.initBindings();
    recognizer = sherpa.OfflineRecognizer(
      sherpa.OfflineRecognizerConfig(
        model: sherpa.OfflineModelConfig(
          whisper: sherpa.OfflineWhisperModelConfig(
            encoder: init.encoder,
            decoder: init.decoder,
            language: 'en',
            task: 'transcribe',
          ),
          tokens: init.tokens,
          numThreads: 4,
          debug: false,
        ),
      ),
    );

    raf = await File(init.wavPath).open();
    final dataLength = await raf.length() - WavFileWriter.headerBytes;
    final texts = <String>[];
    for (var i = 0; i < init.startsMs.length; i++) {
      final from = (init.startsMs[i] * _bytesPerMs).clamp(0, dataLength);
      final to = (init.endsMs[i] * _bytesPerMs).clamp(from, dataLength);
      var text = '';
      if (to - from >= _bytesPerMs * 200) {
        await raf.setPosition(WavFileWriter.headerBytes + from);
        final bytes = await raf.read((to - from) & ~1);
        final stream = recognizer.createStream();
        stream.acceptWaveform(
          samples: pcm16ToFloat32(Uint8List.fromList(bytes)),
          sampleRate: 16000,
        );
        recognizer.decode(stream);
        text = _cleanWhisperText(recognizer.getResult(stream).text);
        stream.free();
      }
      texts.add(text);
      out.send((i + 1) / init.startsMs.length);
    }
    out.send(texts);
  } catch (e) {
    out.send('Final pass failed: $e');
  } finally {
    await raf?.close();
    recognizer?.free();
  }
}

/// Whisper invents filler on near-silent windows; treat those as empty so
/// the live text is kept instead.
String _cleanWhisperText(String raw) {
  final text = raw.trim();
  const hallucinations = {
    'thank you.',
    'thanks for watching!',
    'thank you for watching.',
    '[blank_audio]',
    '(silence)',
    '[music]',
  };
  return hallucinations.contains(text.toLowerCase()) ? '' : text;
}

enum FinalPassStatus { running, failed }

class FinalPassState {
  const FinalPassState(this.status, {this.progress = 0, this.error});

  final FinalPassStatus status;
  final double progress;
  final String? error;
}

/// Tracks final passes per meeting id so the detail screen can show progress
/// and the notification can mirror it while the app is in the background.
class FinalPassNotifier extends Notifier<Map<String, FinalPassState>> {
  @override
  Map<String, FinalPassState> build() => const {};

  void _set(String id, FinalPassState? s) {
    final next = {...state};
    if (s == null) {
      next.remove(id);
    } else {
      next[id] = s;
    }
    state = next;
  }

  /// Whether a final pass can run for [meeting] right now.
  Future<bool> canRun(Meeting meeting) async {
    final modelId = finalPassModelId(ref.read(settingsProvider).finalPassModel);
    final audio = meeting.audioPath;
    return modelId != null &&
        audio != null &&
        meeting.finalSegments.isNotEmpty &&
        await File(audio).exists() &&
        await ref.read(modelDownloadServiceProvider).isReady(modelId);
  }

  /// Re-transcribes [meetingId] and swaps in the result. Afterwards applies
  /// the "delete immediately" audio retention, since the final transcript
  /// now exists. Stops the foreground service if one is still showing.
  Future<void> run(String meetingId) async {
    if (state[meetingId]?.status == FinalPassStatus.running) return;
    final meetings = ref.read(meetingsProvider.notifier);
    final meeting = meetings.byId(meetingId);
    final modelId = finalPassModelId(ref.read(settingsProvider).finalPassModel);
    if (meeting == null || modelId == null || meeting.audioPath == null) {
      return;
    }

    _set(meetingId, const FinalPassState(FinalPassStatus.running));
    var lastShown = -1;
    try {
      final chunks = planFinalPassChunks(meeting.segments);
      final segments = await transcribeWithWhisper(
        meetingId: meetingId,
        wavPath: meeting.audioPath!,
        model: await ref
            .read(modelDownloadServiceProvider)
            .whisperPaths(modelId),
        chunks: chunks,
        onProgress: (p) {
          _set(meetingId, FinalPassState(FinalPassStatus.running, progress: p));
          final pct = (p * 100).round();
          if (pct != lastShown) {
            lastShown = pct;
            unawaited(
              RecordingForegroundService.showStatus(
                title: meeting.title,
                text: 'Improving transcript • $pct%',
              ),
            );
          }
        },
      );
      await meetings.replaceSegments(
        meetingId,
        segments,
        source: TranscriptSource.finalPass,
      );
      if (ref.read(settingsProvider).audioRetention ==
          AudioRetention.deleteImmediately) {
        await meetings.deleteAudio(meetingId);
      }
      _set(meetingId, null);
    } catch (e) {
      _set(
        meetingId,
        const FinalPassState(
          FinalPassStatus.failed,
          error: "Couldn't improve the transcript. The live version is kept.",
        ),
      );
    } finally {
      await RecordingForegroundService.stop();
    }
  }
}

final finalPassProvider =
    NotifierProvider<FinalPassNotifier, Map<String, FinalPassState>>(
      FinalPassNotifier.new,
    );
