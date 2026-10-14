import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:backseat/core/db/app_database.dart';
import 'package:backseat/core/models/meeting.dart';
import 'package:backseat/core/models/segment.dart';
import 'package:backseat/core/models/settings_state.dart';
import 'package:backseat/core/providers/app_providers.dart';
import 'package:backseat/core/storage/api_key_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../fixtures.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Meeting meeting(String id) => Meeting(
    id: id,
    title: 'T $id',
    extraTerms: const ['Churnwatch'],
    startedAt: DateTime(2026, 10, 14, 9),
  );

  Segment seg(String id, int startSec, {bool isFinal = true}) => Segment(
    id: id,
    start: Duration(seconds: startSec),
    end: Duration(seconds: startSec + 3),
    text: 'text $id',
    isFinal: isFinal,
  );

  test(
    'meetings round-trip with extra terms, audio path and segments',
    () async {
      await db.insertMeeting(meeting('m1'));
      await db.upsertSegment('m1', seg('m1_b', 10));
      await db.upsertSegment('m1', seg('m1_a', 0));
      await db.setAudioPath('m1', '/x/m1.wav');

      final loaded = (await db.loadAllMeetings()).single;
      expect(loaded.extraTerms, ['Churnwatch']);
      expect(loaded.audioPath, '/x/m1.wav');
      expect(loaded.segments.map((s) => s.id), ['m1_a', 'm1_b']);
    },
  );

  test('replaceSegments swaps the transcript and marks it final', () async {
    await db.insertMeeting(meeting('m1'));
    await db.insertMeeting(meeting('m2'));
    await db.upsertSegment('m1', seg('m1_live', 0));
    await db.upsertSegment('m2', seg('m2_live', 0));

    await db.replaceSegments('m1', [
      seg('m1_final_0', 0),
      seg('m1_final_1', 20),
    ], source: TranscriptSource.finalPass);

    final all = await db.loadAllMeetings();
    final m1 = all.firstWhere((m) => m.id == 'm1');
    final m2 = all.firstWhere((m) => m.id == 'm2');
    expect(m1.segments.map((s) => s.id), ['m1_final_0', 'm1_final_1']);
    expect(m1.transcriptSource, TranscriptSource.finalPass);
    expect(m2.segments.single.id, 'm2_live');
  });

  test('deleteMeeting removes segments and analyses', () async {
    for (final m in buildFixtureMeetings()) {
      await db.insertMeeting(m);
      for (final s in m.segments) {
        await db.upsertSegment(m.id, s);
      }
      for (final a in m.analyses) {
        await db.insertAnalysis(m.id, a);
      }
    }
    await db.deleteMeeting('meeting-churn');
    final ids = (await db.loadAllMeetings()).map((m) => m.id);
    expect(ids, isNot(contains('meeting-churn')));
    expect(
      (await db.select(db.segments).get()).where(
        (s) => s.meetingId == 'meeting-churn',
      ),
      isEmpty,
    );
  });

  test('settings and prefs persist through StoredPrefs.load', () async {
    const settings = SettingsState(
      analysisModel: 'claude-opus-5-5',
      finalPassModel: FinalPassModel.whisperBaseEn,
      customVocabulary: ['dbt'],
      docDomains: ['learn.microsoft.com'],
      maxDocLookups: 3,
    );
    await db.putSetting(PrefKeys.settings, jsonEncode(settings.toJson()));
    await db.putSetting(PrefKeys.onboardingComplete, 'true');
    await db.putSetting(PrefKeys.themeMode, 'light');

    final prefs = await StoredPrefs.load(db, InMemoryApiKeyStore('sk-ant-x'));
    expect(prefs.onboardingComplete, isTrue);
    expect(prefs.themeMode.name, 'light');
    expect(prefs.settings.hasApiKey, isTrue);
    expect(prefs.settings.analysisModel, 'claude-opus-5-5');
    expect(prefs.settings.finalPassModel, FinalPassModel.whisperBaseEn);
    expect(prefs.settings.customVocabulary, ['dbt']);
    expect(prefs.settings.maxDocLookups, 3);
  });

  test('a meeting left open by a crash is closed on load', () async {
    await db.insertMeeting(meeting('crashed'));
    await db.upsertSegment('crashed', seg('crashed_0', 0));
    await db.upsertSegment('crashed', seg('crashed_1', 30, isFinal: false));

    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        apiKeyStoreProvider.overrideWithValue(InMemoryApiKeyStore()),
      ],
    );
    addTearDown(container.dispose);
    final meetings = await container.read(meetingsProvider.future);
    final recovered = meetings.single;
    expect(recovered.isLive, isFalse);
    expect(recovered.segments.map((s) => s.id), ['crashed_0']);
    expect(
      recovered.endedAt,
      DateTime(2026, 10, 14, 9).add(const Duration(seconds: 3)),
    );
  });

  test('normalizeDomain', () {
    expect(
      normalizeDomain('https://Docs.GetDbt.com/reference'),
      'docs.getdbt.com',
    );
    expect(normalizeDomain('learn.microsoft.com'), 'learn.microsoft.com');
    expect(normalizeDomain('localhost'), isNull);
    expect(normalizeDomain('  '), isNull);
  });
}
