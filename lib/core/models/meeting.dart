import 'analysis.dart';
import 'segment.dart';

enum TranscriptSource { live, finalPass }

class Meeting {
  const Meeting({
    required this.id,
    required this.title,
    this.contextNote,
    this.extraTerms = const [],
    required this.startedAt,
    this.endedAt,
    this.audioPath,
    this.transcriptSource = TranscriptSource.live,
    this.segments = const [],
    this.analyses = const [],
  });

  final String id;
  final String title;
  final String? contextNote;

  /// Per-meeting vocabulary (project names, acronyms) added in the start
  /// sheet, used alongside the global list for ASR biasing and analysis.
  final List<String> extraTerms;
  final DateTime startedAt;
  final DateTime? endedAt;

  /// Local WAV recording, null once deleted per the retention setting.
  final String? audioPath;
  final TranscriptSource transcriptSource;
  final List<Segment> segments;
  final List<Analysis> analyses;

  bool get isLive => endedAt == null;

  Duration get duration {
    final end = endedAt ?? DateTime.now();
    return end.difference(startedAt);
  }

  List<Segment> get finalSegments => segments.where((s) => s.isFinal).toList();

  String get transcriptText =>
      segments.where((s) => s.isFinal).map((s) => s.text).join(' ');

  Meeting copyWith({
    String? title,
    String? contextNote,
    List<String>? extraTerms,
    DateTime? endedAt,
    String? audioPath,
    bool clearAudioPath = false,
    TranscriptSource? transcriptSource,
    List<Segment>? segments,
    List<Analysis>? analyses,
  }) {
    return Meeting(
      id: id,
      title: title ?? this.title,
      contextNote: contextNote ?? this.contextNote,
      extraTerms: extraTerms ?? this.extraTerms,
      startedAt: startedAt,
      endedAt: endedAt ?? this.endedAt,
      audioPath: clearAudioPath ? null : audioPath ?? this.audioPath,
      transcriptSource: transcriptSource ?? this.transcriptSource,
      segments: segments ?? this.segments,
      analyses: analyses ?? this.analyses,
    );
  }
}
