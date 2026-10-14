import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:backseat/core/models/meeting.dart';

import 'test_utils.dart';

void main() {
  testWidgets('Start sheet -> Live meeting -> Analyse -> Stop saves meeting', (
    tester,
  ) async {
    final analysis = FakeAnalysisService();
    final db = await pumpAppOnHome(tester, analysis: analysis);

    await tester.tap(find.text('Start listening'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Meeting title (optional)'),
      'Test sync',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Extra terms (optional)'),
      'Churnwatch, CLV',
    );

    await tester.tap(find.widgetWithText(ElevatedButton, 'Start'));
    await tester.pumpAndSettle();
    // Let the fake engine replay a few lines (word-by-word, ~3 s per line).
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    await settleAsync(tester);

    expect(find.text('Recording'), findsOneWidget);
    expect(find.text('Test sync'), findsOneWidget);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Analyse'));
    await tester.pumpAndSettle();

    expect(analysis.calls, 1);
    expect(find.text('Analysis'), findsOneWidget);
    expect(find.textContaining('Issues & suggestions'), findsOneWidget);

    // Close the sheet, then stop: lands on the detail screen.
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Stop'));
    await settleAsync(tester);

    expect(find.text('Live draft'), findsOneWidget);
    final saved = (await db.loadAllMeetings()).firstWhere(
      (m) => m.title == 'Test sync',
    );
    expect(saved.endedAt, isNotNull);
    expect(saved.extraTerms, ['Churnwatch', 'CLV']);
    expect(saved.analyses, hasLength(1));
    expect(saved.transcriptSource, TranscriptSource.live);
    // Only finalised segments are persisted, each id scoped to the meeting.
    expect(saved.segments, isNotEmpty);
    expect(saved.segments.every((s) => s.isFinal), isTrue);
    expect(saved.segments.every((s) => s.id.startsWith(saved.id)), isTrue);

    await tester.pumpWidget(const SizedBox());
  });
}
