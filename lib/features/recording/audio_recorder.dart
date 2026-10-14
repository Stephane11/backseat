import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:record/record.dart';

import 'wav_file_writer.dart';

class RecordedAudio {
  const RecordedAudio({required this.pcm16, required this.level});

  final Uint8List pcm16;

  /// Peak amplitude of this chunk, normalized 0.0-1.0, for the level meter.
  final double level;
}

/// Wraps the `record` plugin: PCM16 16kHz mono streaming capture tee'd to
/// (a) a WAV file on disk and (b) a broadcast stream for the ASR engine,
/// matching the brief §3 pipeline.
class AppAudioRecorder {
  final _recorder = AudioRecorder();
  final _controller = StreamController<RecordedAudio>.broadcast();

  StreamSubscription<Uint8List>? _sub;
  WavFileWriter? _wavWriter;

  Stream<RecordedAudio> get audioStream => _controller.stream;

  static const sampleRate = 16000;
  static const numChannels = 1;

  Future<bool> hasPermission() => _recorder.hasPermission();

  Future<void> start({required String wavFilePath}) async {
    _wavWriter = WavFileWriter(
      File(wavFilePath),
      sampleRate: sampleRate,
      numChannels: numChannels,
    );
    await _wavWriter!.open();

    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: sampleRate,
        numChannels: numChannels,
        // Room audio from laptop speakers: let the platform clean it up.
        noiseSuppress: true,
        autoGain: true,
      ),
    );
    _sub = stream.listen((chunk) {
      unawaited(_wavWriter?.writeChunk(chunk));
      _controller.add(RecordedAudio(pcm16: chunk, level: _peakLevel(chunk)));
    });
  }

  double _peakLevel(Uint8List bytes) {
    var peak = 0;
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      final sample = bytes[i] | (bytes[i + 1] << 8);
      final signed = sample >= 0x8000 ? sample - 0x10000 : sample;
      final abs = signed.abs();
      if (abs > peak) peak = abs;
    }
    return (peak / 32768).clamp(0.0, 1.0);
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    if (await _recorder.isRecording()) await _recorder.stop();
    await _wavWriter?.close();
    _wavWriter = null;
  }

  Future<void> dispose() async {
    await stop();
    await _controller.close();
    await _recorder.dispose();
  }
}
