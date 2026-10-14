class Segment {
  const Segment({
    required this.id,
    required this.start,
    required this.end,
    required this.text,
    required this.isFinal,
  });

  final String id;
  final Duration start;
  final Duration end;
  final String text;
  final bool isFinal;

  Segment copyWith({String? id, Duration? end, String? text, bool? isFinal}) {
    return Segment(
      id: id ?? this.id,
      start: start,
      end: end ?? this.end,
      text: text ?? this.text,
      isFinal: isFinal ?? this.isFinal,
    );
  }
}
