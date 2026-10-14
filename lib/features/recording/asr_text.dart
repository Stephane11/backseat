// Text helpers around the streaming Zipformer model, whose vocabulary is
// upper-case BPE (it emits "WE ARE USING UNITY CATALOG").

/// Turns raw upper-case recogniser output into readable sentence case and
/// restores the canonical spelling of known vocabulary terms
/// ("unity catalog" -> "Unity Catalog", "pyspark" -> "PySpark").
String normalizeLiveText(String raw, List<String> vocabulary) {
  var text = raw.trim().toLowerCase();
  if (text.isEmpty) return text;

  text = text.replaceAllMapped(RegExp(r"\bi(?=\b|')"), (_) => 'I');

  final terms = [...vocabulary]..sort((a, b) => b.length.compareTo(a.length));
  for (final term in terms) {
    final words = _spokenWords(term);
    if (words.isEmpty) continue;
    final pattern = RegExp(
      '\\b${words.map(RegExp.escape).join(r'\s+')}\\b',
      caseSensitive: false,
    );
    text = text.replaceAll(pattern, term);
  }

  return text[0].toUpperCase() + text.substring(1);
}

/// Formats vocabulary as a sherpa-onnx per-stream hotwords string: one
/// phrase per entry separated by `/`, upper-cased to match the model's BPE
/// pieces, punctuation the model can't emit turned into word breaks.
String formatHotwords(Iterable<String> terms) {
  final seen = <String>{};
  final phrases = <String>[];
  for (final term in terms) {
    final words = _spokenWords(term);
    if (words.isEmpty) continue;
    final phrase = words.join(' ').toUpperCase();
    if (seen.add(phrase)) phrases.add(phrase);
  }
  return phrases.join('/');
}

/// "CI/CD" -> [ci, cd]; "scikit-learn" -> [scikit, learn].
List<String> _spokenWords(String term) => term
    .toLowerCase()
    .split(RegExp(r"[^a-z0-9']+"))
    .where((w) => w.isNotEmpty)
    .toList();
