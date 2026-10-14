import '../../core/models/segment.dart';

/// Source of transcript segments for a live meeting. Implementations emit a
/// [Segment] with `isFinal: false` while an utterance is still being spoken,
/// then re-emit the same id with `isFinal: true` once it settles — the UI
/// upserts by id either way. Swappable so the fake (tests/dev) and real
/// sherpa-onnx streaming engines can sit behind the Live meeting screen
/// without it changing; the Whisper final pass runs separately after Stop.
abstract class TranscriptionEngine {
  Stream<Segment> get segments;

  /// Emits a running 0.0-1.0 input level so the UI can show a level meter.
  Stream<double> get audioLevel;

  /// Where the raw audio is being written, or null if nothing is recorded
  /// (the fake engine). Used later for the Whisper final pass.
  String? get audioPath;

  /// Throws [TranscriptionStartException] with a user-facing message when
  /// the engine can't start (missing model, microphone denied).
  Future<void> start();
  Future<void> stop();
  Future<void> dispose();
}

class TranscriptionStartException implements Exception {
  const TranscriptionStartException(this.message, {this.needsModel = false});

  final String message;
  final bool needsModel;

  @override
  String toString() => message;
}
