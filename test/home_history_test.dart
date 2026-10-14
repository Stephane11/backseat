import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_utils.dart';

void main() {
  testWidgets('Home lists fixture meetings and search filters them', (
    tester,
  ) async {
    await pumpAppOnHome(tester);

    expect(find.text('Churn model v2 review'), findsOneWidget);
    expect(find.text('Weekly data platform sync'), findsOneWidget);
    expect(find.text('RAG eval kickoff'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'churn');
    await tester.pumpAndSettle();

    expect(find.text('Churn model v2 review'), findsOneWidget);
    expect(find.text('Weekly data platform sync'), findsNothing);
  });

  testWidgets('Tapping a past meeting opens its detail screen', (tester) async {
    await pumpAppOnHome(tester);

    await tester.tap(find.text('Churn model v2 review'));
    await tester.pumpAndSettle();

    expect(find.text('Analyses'), findsOneWidget);
    expect(find.text('Final transcript'), findsOneWidget);
    expect(find.text('Transcript'), findsOneWidget);
  });

  testWidgets('Settings gear opens Settings screen', (tester) async {
    await pumpAppOnHome(tester);

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Claude API'), findsOneWidget);
  });
}
