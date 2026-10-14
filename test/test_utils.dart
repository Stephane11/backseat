import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/misc.dart' show Override;

import 'package:backseat/core/db/app_database.dart';
import 'package:backseat/core/models/meeting.dart';
import 'package:backseat/core/models/settings_state.dart';
import 'package:backseat/core/providers/app_providers.dart';
import 'package:backseat/core/storage/api_key_store.dart';
import 'package:backseat/features/analysis/analysis_service.dart';
import 'package:backseat/features/recording/fake_transcription_engine.dart';
import 'package:backseat/features/recording/model_download_service.dart';
import 'package:backseat/features/recording/transcription_engine_provider.dart';
import 'package:backseat/main.dart';

import 'fixtures.dart';

/// An in-memory [AppDatabase], seeded with hand-written fixture meetings.
Future<AppDatabase> createSeededTestDatabase() async {
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  for (final meeting in buildFixtureMeetings()) {
    await db.insertMeeting(meeting);
    for (final segment in meeting.segments) {
      await db.upsertSegment(meeting.id, segment);
    }
    for (final analysis in meeting.analyses) {
      await db.insertAnalysis(meeting.id, analysis);
    }
    if (meeting.endedAt != null) {
      await db.stopMeeting(meeting.id, meeting.endedAt!);
    }
  }
  return db;
}

/// Models are "already downloaded" and downloads finish instantly.
class FakeModelDownloadService extends ModelDownloadService {
  FakeModelDownloadService({this.ready = true});

  bool ready;

  @override
  Future<bool> isReady(AsrModelId id) async => ready;

  @override
  Future<void> download(
    AsrModelId id, {
    required void Function(double progress) onProgress,
    CancelToken? cancelToken,
  }) async {
    onProgress(1);
    ready = true;
  }
}

/// Stands in for the Claude call: surfaces the canned churn-review cards
/// whose evidence appears in the transcript so far.
class FakeAnalysisService implements AnalysisService {
  int calls = 0;

  @override
  Future<AnalysisOutcome> analyse(
    Meeting meeting, {
    required bool checkDocs,
    StatusCallback? onStatus,
    CancelToken? cancelToken,
  }) async {
    calls++;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return AnalysisSucceeded(
      buildMockAnalysis(
        finalSegments: meeting.finalSegments,
        model: 'claude-sonnet-5-5',
      ),
    );
  }
}

/// Overrides every platform-backed provider so widgets run in a test VM.
List<Override> baseTestOverrides(
  AppDatabase db, {
  StoredPrefs prefs = const StoredPrefs(
    onboardingComplete: true,
    privacyNoticeAcknowledged: true,
    settings: SettingsState(hasApiKey: true),
  ),
  ApiKeyStore? keyStore,
  ModelDownloadService? downloads,
  AnalysisService? analysis,
}) => [
  databaseProvider.overrideWithValue(db),
  initialPrefsProvider.overrideWithValue(prefs),
  apiKeyStoreProvider.overrideWithValue(
    keyStore ?? InMemoryApiKeyStore('sk-ant-test'),
  ),
  modelDownloadServiceProvider.overrideWithValue(
    downloads ?? FakeModelDownloadService(),
  ),
  analysisServiceProvider.overrideWithValue(analysis ?? FakeAnalysisService()),
  transcriptionEngineBuilderProvider.overrideWithValue(
    (meeting) async => FakeTranscriptionEngine(),
  ),
];

/// Turns on the system "remove animations" setting so looping animations
/// (recording pulse, loading skeletons) don't keep pumpAndSettle busy.
void disableAnimations(WidgetTester tester) {
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
}

/// Pumps the full app with onboarding already complete and the database
/// seeded with fixtures, so tests land directly on Home.
Future<AppDatabase> pumpAppOnHome(
  WidgetTester tester, {
  List<Override> overrides = const [],
  AnalysisService? analysis,
}) async {
  disableAnimations(tester);
  final db = await createSeededTestDatabase();
  addTearDown(db.close);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...baseTestOverrides(db, analysis: analysis),
        ...overrides,
      ],
      child: const BackseatApp(),
    ),
  );
  await tester.pumpAndSettle();
  return db;
}

/// pumpAndSettle only waits while frames are scheduled; async work that
/// schedules none (stream cancels, database writes) can still be pending.
/// Alternate real-time waits with pumps until the UI is quiet.
Future<void> settleAsync(WidgetTester tester, {int rounds = 5}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
  }
}
