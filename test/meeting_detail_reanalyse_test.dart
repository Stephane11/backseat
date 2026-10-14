import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:backseat/core/models/settings_state.dart';
import 'package:backseat/core/providers/app_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:backseat/main.dart';

import 'test_utils.dart';

void main() {
  testWidgets('Analyse on a past meeting adds and opens a new analysis', (
    tester,
  ) async {
    final db = await pumpAppOnHome(tester);

    await tester.tap(find.text('RAG eval kickoff'));
    await tester.pumpAndSettle();

    expect(find.text('No analyses yet.'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Analyse'));
    await tester.pumpAndSettle();

    expect(find.text('Analysis'), findsOneWidget);
    final meeting = (await db.loadAllMeetings()).firstWhere(
      (m) => m.title == 'RAG eval kickoff',
    );
    expect(meeting.analyses, hasLength(1));
  });

  testWidgets('without an API key, Analyse points to Settings', (tester) async {
    disableAnimations(tester);
    final db = await createSeededTestDatabase();
    addTearDown(db.close);
    final analysis = FakeAnalysisService();
    await tester.pumpWidget(
      ProviderScope(
        overrides: baseTestOverrides(
          db,
          prefs: const StoredPrefs(
            onboardingComplete: true,
            settings: SettingsState(),
          ),
          analysis: analysis,
        ),
        child: const BackseatApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('RAG eval kickoff'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Analyse'));
    await tester.pumpAndSettle();

    expect(
      find.text('Add your Claude API key to analyse meetings.'),
      findsOneWidget,
    );
    expect(analysis.calls, 0);
  });

  testWidgets('first analysis shows the privacy notice once', (tester) async {
    disableAnimations(tester);
    final seeded = await createSeededTestDatabase();
    addTearDown(seeded.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: baseTestOverrides(
          seeded,
          prefs: const StoredPrefs(
            onboardingComplete: true,
            settings: SettingsState(hasApiKey: true),
          ),
        ),
        child: const BackseatApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('RAG eval kickoff'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Analyse'));
    await tester.pumpAndSettle();

    expect(find.text('Before your first analysis'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Analysis'), findsOneWidget);
    expect(await seeded.getSetting(PrefKeys.privacyNoticeAcknowledged), 'true');
  });
}
