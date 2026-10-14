import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:backseat/core/db/app_database.dart';
import 'package:backseat/core/models/settings_state.dart';
import 'package:backseat/core/providers/app_providers.dart';
import 'package:backseat/core/storage/api_key_store.dart';
import 'package:backseat/core/theme/app_theme.dart';
import 'package:backseat/features/settings/settings_screen.dart';

import 'test_utils.dart';

void main() {
  late AppDatabase db;
  late InMemoryApiKeyStore keyStore;
  late ProviderContainer container;

  // The Settings list is tall; give the test surface enough height that
  // every field builds without needing to scroll it into view first.
  Future<void> pumpSettings(
    WidgetTester tester, {
    StoredPrefs prefs = const StoredPrefs(onboardingComplete: true),
  }) async {
    tester.view.physicalSize = const Size(1080, 6000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    disableAnimations(tester);

    db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    keyStore = InMemoryApiKeyStore();
    container = ProviderContainer(
      overrides: baseTestOverrides(db, prefs: prefs, keyStore: keyStore),
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const SettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'shows defaults from SettingsState, including delete-immediately retention',
    (tester) async {
      await pumpSettings(tester);

      expect(find.text('claude-sonnet-5-5 (faster)'), findsOneWidget);
      expect(
        find.text('Delete immediately after final transcript'),
        findsOneWidget,
      );
      expect(find.text('learn.microsoft.com'), findsOneWidget);
      for (final term in kStarterVocabulary.take(3)) {
        expect(find.text(term), findsOneWidget);
      }
    },
  );

  testWidgets('switching appearance updates and persists the theme', (
    tester,
  ) async {
    await pumpSettings(tester);

    expect(container.read(themeModeProvider), ThemeMode.dark);

    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();

    expect(container.read(themeModeProvider), ThemeMode.light);
    expect(await db.getSetting(PrefKeys.themeMode), 'light');
  });

  testWidgets('adding a custom vocabulary term shows it and persists it', (
    tester,
  ) async {
    await pumpSettings(tester);

    await tester.enterText(
      find.widgetWithText(TextField, 'Add term'),
      'Kubeflow',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.widgetWithText(InputChip, 'Kubeflow'), findsOneWidget);
    final saved = SettingsState.fromJson(
      jsonDecode((await db.getSetting(PrefKeys.settings))!)
          as Map<String, dynamic>,
    );
    expect(saved.customVocabulary, contains('Kubeflow'));
  });

  testWidgets('saving an API key stores it securely and shows it as saved', (
    tester,
  ) async {
    await pumpSettings(tester);

    await tester.enterText(
      find.widgetWithText(TextField, 'API key'),
      'sk-ant-abc123',
    );
    await tester.tap(find.byTooltip('Save'));
    await tester.pumpAndSettle();

    expect(await keyStore.read(), 'sk-ant-abc123');
    expect(container.read(settingsProvider).hasApiKey, isTrue);
    expect(find.text('API key saved on this device'), findsOneWidget);

    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(await keyStore.read(), isNull);
    expect(container.read(settingsProvider).hasApiKey, isFalse);
  });

  testWidgets('rejects text that is not an API key', (tester) async {
    await pumpSettings(tester);

    await tester.enterText(find.widgetWithText(TextField, 'API key'), 'hello');
    await tester.tap(find.byTooltip('Save'));
    await tester.pumpAndSettle();

    expect(await keyStore.read(), isNull);
    expect(find.textContaining("doesn't look like"), findsOneWidget);
  });

  testWidgets('adding a doc domain normalises URLs to a hostname', (
    tester,
  ) async {
    await pumpSettings(tester);

    await tester.enterText(
      find.widgetWithText(TextField, 'Add approved domain'),
      'https://docs.getdbt.com/reference/',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(
      container.read(settingsProvider).docDomains,
      contains('docs.getdbt.com'),
    );
  });
}
