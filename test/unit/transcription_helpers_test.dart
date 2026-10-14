import 'package:flutter_test/flutter_test.dart';

import 'package:backseat/core/models/segment.dart';
import 'package:backseat/features/recording/asr_text.dart';
import 'package:backseat/features/transcript/final_pass.dart';
import 'package:backseat/shared/formatting.dart';

Segment seg(double start, double end, String text, {bool isFinal = true}) =>
    Segment(
      id: '$start',
      start: Duration(milliseconds: (start * 1000).round()),
      end: Duration(milliseconds: (end * 1000).round()),
      text: text,
      isFinal: isFinal,
    );

void main() {
  group('normalizeLiveText', () {
    test('sentence-cases upper-case output and restores vocabulary', () {
      expect(
        normalizeLiveText(
          'WE MOVED THE TABLES INTO UNITY CATALOG AND I THINK PYSPARK IS FINE',
          ['Unity Catalog', 'PySpark'],
        ),
        'We moved the tables into Unity Catalog and I think PySpark is fine',
      );
    });

    test('handles punctuation-bearing terms', () {
      expect(
        normalizeLiveText('THE CI CD PIPELINE USES SCIKIT LEARN', [
          'CI/CD',
          'scikit-learn',
        ]),
        'The CI/CD pipeline uses scikit-learn',
      );
    });

    test('empty stays empty', () => expect(normalizeLiveText('  ', []), ''));
  });

  test('formatHotwords upper-cases, splits punctuation and dedupes', () {
    expect(
      formatHotwords([
        'Unity Catalog',
        'CI/CD',
        'scikit-learn',
        'unity catalog',
      ]),
      'UNITY CATALOG/CI CD/SCIKIT LEARN',
    );
  });

  group('planFinalPassChunks', () {
    test('groups close segments up to 25 s and splits on long gaps', () {
      final chunks = planFinalPassChunks([
        seg(0, 5, 'a'),
        seg(5.5, 12, 'b'),
        seg(12.5, 22, 'c'),
        seg(23, 30, 'd'), // would exceed 25 s span from 0
        seg(40, 45, 'e'), // > 3 s gap
        seg(45, 46, 'partial', isFinal: false),
      ]);
      expect(chunks.map((c) => c.liveText), ['a b c', 'd', 'e']);
      expect(chunks.first.start, Duration.zero); // padding clamped at 0
      expect(chunks.first.end, const Duration(milliseconds: 22250));
      expect(chunks[2].start, const Duration(milliseconds: 39750));
      for (final c in chunks) {
        expect(c.end - c.start <= const Duration(seconds: 26), isTrue);
      }
    });

    test('no segments, no chunks', () {
      expect(planFinalPassChunks(const []), isEmpty);
    });
  });

  group('hms', () {
    test('formats and parses', () {
      expect(
        formatHms(const Duration(hours: 1, minutes: 2, seconds: 3)),
        '01:02:03',
      );
      expect(
        parseHms('01:02:03'),
        const Duration(hours: 1, minutes: 2, seconds: 3),
      );
      expect(parseHms('[00:12:34]'), const Duration(minutes: 12, seconds: 34));
      expect(parseHms('2:05'), const Duration(minutes: 2, seconds: 5));
      expect(parseHms('null'), isNull);
      expect(parseHms(null), isNull);
    });
  });
}
