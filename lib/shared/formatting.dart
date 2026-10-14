String formatTimer(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  if (h > 0) {
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

String formatTimestamp(Duration d) => formatTimer(d);

/// Always `hh:mm:ss`, the format used in prompts and the analysis schema.
String formatHms(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.inHours)}:${two(d.inMinutes.remainder(60))}:'
      '${two(d.inSeconds.remainder(60))}';
}

/// Parses `hh:mm:ss` or `mm:ss` (optionally bracketed); null otherwise.
Duration? parseHms(String? input) {
  if (input == null) return null;
  final match = RegExp(r'^\[?(?:(\d{1,2}):)?(\d{1,2}):(\d{2})\]?$')
      .firstMatch(input.trim());
  if (match == null) return null;
  return Duration(
    hours: int.parse(match.group(1) ?? '0'),
    minutes: int.parse(match.group(2)!),
    seconds: int.parse(match.group(3)!),
  );
}

String formatRelativeDate(DateTime dateTime) {
  final now = DateTime.now();
  final date = DateTime(dateTime.year, dateTime.month, dateTime.day);
  final today = DateTime(now.year, now.month, now.day);
  final diff = today.difference(date).inDays;

  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  if (diff < 7) return '$diff days ago';

  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[dateTime.month - 1]} ${dateTime.day}';
}

String greetingForNow() {
  final hour = DateTime.now().hour;
  if (hour < 12) return 'Good morning';
  if (hour < 18) return 'Good afternoon';
  return 'Good evening';
}
