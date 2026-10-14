import 'dart:async';
import 'dart:math';

import 'package:flutter/services.dart';

import '../../core/models/segment.dart';
import 'transcription_engine.dart';

/// Replays `assets/sample_transcript.txt` word-by-word so the app can be
/// built, demoed and widget-tested without a real microphone (brief §2, §8).
class FakeTranscriptionEngine implements TranscriptionEngine {
  FakeTranscriptionEngine({
    this.wordInterval = const Duration(milliseconds: 220),
  });

  final Duration wordInterval;
  final _segmentsController = StreamController<Segment>.broadcast();
  final _levelController = StreamController<double>.broadcast();
  final _random = Random();

  Timer? _timer;
  bool _running = false;
  List<String> _lines = [];
  int _lineIndex = 0;

  @override
  Stream<Segment> get segments => _segmentsController.stream;

  @override
  Stream<double> get audioLevel => _levelController.stream;

  @override
  String? get audioPath => null;

  @override
  Future<void> start() async {
    if (_running) return;
    _running = true;
    final raw = await rootBundle.loadString('assets/sample_transcript.txt');
    _lines = raw
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    _lineIndex = 0;
    _emitNextLine();
  }

  void _emitNextLine() {
    if (!_running || _lineIndex >= _lines.length) return;

    final line = _lines[_lineIndex];
    final words = line.split(' ');
    final id = 'fake-seg-$_lineIndex';
    final start = Duration(seconds: _lineIndex * 9);
    var wordCount = 0;

    void emitPartial() {
      if (!_running) return;
      wordCount++;
      _levelController.add(0.2 + _random.nextDouble() * 0.6);
      final isDone = wordCount >= words.length;
      _segmentsController.add(
        Segment(
          id: id,
          start: start,
          end: start + wordInterval * wordCount,
          text: words.take(wordCount).join(' '),
          isFinal: isDone,
        ),
      );
      if (isDone) {
        _lineIndex++;
        _timer = Timer(const Duration(milliseconds: 500), _emitNextLine);
      } else {
        _timer = Timer(wordInterval, emitPartial);
      }
    }

    emitPartial();
  }

  @override
  Future<void> stop() async {
    _running = false;
    _timer?.cancel();
    _levelController.add(0);
  }

  @override
  Future<void> dispose() async {
    _timer?.cancel();
    await _segmentsController.close();
    await _levelController.close();
  }
}
