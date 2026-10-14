import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/app_database.dart';
import '../models/analysis.dart';
import '../models/meeting.dart';
import '../models/segment.dart';
import '../models/settings_state.dart';
import '../storage/api_key_store.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final apiKeyStoreProvider = Provider<ApiKeyStore>((ref) => SecureApiKeyStore());

/// Keys in the Drift `settings` key-value table.
class PrefKeys {
  const PrefKeys._();
  static const settings = 'settings';
  static const onboardingComplete = 'onboarding_complete';
  static const themeMode = 'theme_mode';
  static const privacyNoticeAcknowledged = 'privacy_notice_ack';
}

/// Everything persisted that the first frame needs (router redirect, theme),
/// loaded once in `main()` before `runApp` and injected through
/// [initialPrefsProvider].
class StoredPrefs {
  const StoredPrefs({
    this.settings = const SettingsState(),
    this.onboardingComplete = false,
    this.themeMode = ThemeMode.dark,
    this.privacyNoticeAcknowledged = false,
  });

  final SettingsState settings;
  final bool onboardingComplete;
  final ThemeMode themeMode;
  final bool privacyNoticeAcknowledged;

  static Future<StoredPrefs> load(AppDatabase db, ApiKeyStore keyStore) async {
    final settingsJson = await db.getSetting(PrefKeys.settings);
    var settings = const SettingsState();
    if (settingsJson != null) {
      try {
        settings = SettingsState.fromJson(
          jsonDecode(settingsJson) as Map<String, dynamic>,
        );
      } on FormatException {
        // Corrupt row: fall back to defaults rather than refusing to start.
      }
    }
    String? key;
    try {
      key = await keyStore.read();
    } catch (_) {
      // Keystore can fail after a device restore; treat as "no key".
    }
    final theme = await db.getSetting(PrefKeys.themeMode);
    return StoredPrefs(
      settings: settings.copyWith(hasApiKey: key != null && key.isNotEmpty),
      onboardingComplete:
          await db.getSetting(PrefKeys.onboardingComplete) == 'true',
      themeMode: ThemeMode.values.firstWhere(
        (m) => m.name == theme,
        orElse: () => ThemeMode.dark,
      ),
      privacyNoticeAcknowledged:
          await db.getSetting(PrefKeys.privacyNoticeAcknowledged) == 'true',
    );
  }
}

final initialPrefsProvider = Provider<StoredPrefs>(
  (ref) => const StoredPrefs(),
);

class OnboardingCompleteNotifier extends Notifier<bool> {
  @override
  bool build() => ref.read(initialPrefsProvider).onboardingComplete;

  void complete() {
    state = true;
    unawaited(
      ref
          .read(databaseProvider)
          .putSetting(PrefKeys.onboardingComplete, 'true'),
    );
  }
}

final onboardingCompleteProvider =
    NotifierProvider<OnboardingCompleteNotifier, bool>(
      OnboardingCompleteNotifier.new,
    );

class PrivacyNoticeNotifier extends Notifier<bool> {
  @override
  bool build() => ref.read(initialPrefsProvider).privacyNoticeAcknowledged;

  void acknowledge() {
    state = true;
    unawaited(
      ref
          .read(databaseProvider)
          .putSetting(PrefKeys.privacyNoticeAcknowledged, 'true'),
    );
  }
}

final privacyNoticeAcknowledgedProvider =
    NotifierProvider<PrivacyNoticeNotifier, bool>(PrivacyNoticeNotifier.new);

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ref.read(initialPrefsProvider).themeMode;

  void setMode(ThemeMode mode) {
    state = mode;
    unawaited(
      ref.read(databaseProvider).putSetting(PrefKeys.themeMode, mode.name),
    );
  }
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);

class ActiveMeetingIdNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? id) => state = id;
}

final activeMeetingIdProvider =
    NotifierProvider<ActiveMeetingIdNotifier, String?>(
      ActiveMeetingIdNotifier.new,
    );

class SettingsNotifier extends Notifier<SettingsState> {
  @override
  SettingsState build() => ref.read(initialPrefsProvider).settings;

  void _update(SettingsState next) {
    state = next;
    unawaited(
      ref
          .read(databaseProvider)
          .putSetting(PrefKeys.settings, jsonEncode(next.toJson())),
    );
  }

  Future<void> saveApiKey(String key) async {
    await ref.read(apiKeyStoreProvider).write(key.trim());
    state = state.copyWith(hasApiKey: true);
  }

  Future<void> clearApiKey() async {
    await ref.read(apiKeyStoreProvider).delete();
    state = state.copyWith(hasApiKey: false);
  }

  void setAnalysisModel(String model) =>
      _update(state.copyWith(analysisModel: model));

  void setFinalPassModel(FinalPassModel model) =>
      _update(state.copyWith(finalPassModel: model));

  void setGlobalContextNote(String note) =>
      _update(state.copyWith(globalContextNote: note));

  void setAudioRetention(AudioRetention retention) =>
      _update(state.copyWith(audioRetention: retention));

  void setBoostStrength(double value) =>
      _update(state.copyWith(boostStrength: value));

  void setCheckDocsDefault(bool value) =>
      _update(state.copyWith(checkDocsDefault: value));

  void setWorkspaceId(String value) =>
      _update(state.copyWith(workspaceId: value.trim()));

  void setMaxDocLookups(int value) =>
      _update(state.copyWith(maxDocLookups: value));

  void addVocabularyTerm(String term) {
    final t = term.trim();
    if (t.isEmpty || state.customVocabulary.contains(t)) return;
    _update(state.copyWith(customVocabulary: [...state.customVocabulary, t]));
  }

  void removeVocabularyTerm(String term) {
    _update(
      state.copyWith(
        customVocabulary: state.customVocabulary
            .where((t) => t != term)
            .toList(),
      ),
    );
  }

  /// Replaces the list from an imported file: one term per line, blank lines
  /// and duplicates dropped.
  void replaceVocabulary(List<String> terms) {
    final seen = <String>{};
    final cleaned = [
      for (final t in terms.map((t) => t.trim()))
        if (t.isNotEmpty && seen.add(t)) t,
    ];
    _update(state.copyWith(customVocabulary: cleaned));
  }

  void addDocDomain(String domain) {
    final d = normalizeDomain(domain);
    if (d == null || state.docDomains.contains(d)) return;
    _update(state.copyWith(docDomains: [...state.docDomains, d]));
  }

  void removeDocDomain(String domain) {
    _update(
      state.copyWith(
        docDomains: state.docDomains.where((d) => d != domain).toList(),
      ),
    );
  }
}

/// Accepts "https://learn.microsoft.com/en-us/" or "learn.microsoft.com" and
/// returns the bare hostname the API's `allowed_domains` expects.
String? normalizeDomain(String input) {
  var s = input.trim().toLowerCase();
  if (s.isEmpty) return null;
  if (!s.contains('://')) s = 'https://$s';
  final host = Uri.tryParse(s)?.host ?? '';
  if (!host.contains('.') || host.startsWith('.') || host.endsWith('.')) {
    return null;
  }
  return host;
}

final settingsProvider = NotifierProvider<SettingsNotifier, SettingsState>(
  SettingsNotifier.new,
);

/// Backed by [AppDatabase]: final segments and every other mutation write
/// through to SQLite before updating in-memory state, so a crash loses at
/// most the utterance in flight (brief §7 reliability requirement). Partial
/// (still-being-spoken) segments live only in memory.
class MeetingsNotifier extends AsyncNotifier<List<Meeting>> {
  AppDatabase get _db => ref.read(databaseProvider);

  @override
  Future<List<Meeting>> build() async {
    final meetings = await _db.loadAllMeetings();
    final result = <Meeting>[];
    for (final meeting in meetings) {
      result.add(await _applyAudioRetention(await _recoverIfOrphaned(meeting)));
    }
    return result;
  }

  /// No meeting can be recording at app start, so one with no end time was
  /// interrupted by a crash or the process being killed: close it at its
  /// last transcribed moment so it shows up as a normal past meeting.
  Future<Meeting> _recoverIfOrphaned(Meeting meeting) async {
    if (!meeting.isLive) return meeting;
    final finals = meeting.finalSegments;
    final endedAt = meeting.startedAt.add(
      finals.isEmpty ? Duration.zero : finals.last.end,
    );
    await _db.stopMeeting(meeting.id, endedAt);
    await _db.replaceSegments(
      meeting.id,
      finals,
      source: meeting.transcriptSource,
    );
    return meeting.copyWith(endedAt: endedAt, segments: finals);
  }

  /// "Keep 7 days" cleanup, run once per launch. "Delete immediately" is
  /// handled right after the final transcript is produced.
  Future<Meeting> _applyAudioRetention(Meeting meeting) async {
    final retention = ref.read(settingsProvider).audioRetention;
    final path = meeting.audioPath;
    final endedAt = meeting.endedAt;
    if (retention != AudioRetention.keep7Days ||
        path == null ||
        endedAt == null ||
        endedAt.isAfter(DateTime.now().subtract(const Duration(days: 7)))) {
      return meeting;
    }
    await _deleteFile(path);
    await _db.setAudioPath(meeting.id, null);
    return meeting.copyWith(clearAudioPath: true);
  }

  Future<void> _deleteFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // Already gone or not deletable; the reference is cleared regardless.
    }
  }

  Meeting? byId(String id) {
    for (final meeting in state.value ?? const <Meeting>[]) {
      if (meeting.id == id) return meeting;
    }
    return null;
  }

  void _replace(String meetingId, Meeting Function(Meeting) update) {
    state = AsyncData([
      for (final meeting in state.value ?? const <Meeting>[])
        if (meeting.id == meetingId) update(meeting) else meeting,
    ]);
  }

  Future<Meeting> startMeeting({
    required String title,
    String? contextNote,
    List<String> extraTerms = const [],
  }) async {
    final meeting = Meeting(
      id: 'meeting-${DateTime.now().microsecondsSinceEpoch}',
      title: title.trim().isEmpty ? 'Untitled meeting' : title.trim(),
      contextNote: contextNote,
      extraTerms: extraTerms,
      startedAt: DateTime.now(),
    );
    await _db.insertMeeting(meeting);
    state = AsyncData([meeting, ...state.value ?? const <Meeting>[]]);
    return meeting;
  }

  /// Upserts a segment by id: a repeated id with `isFinal: false` updates the
  /// partial in place, a new id appends, and `isFinal: true` locks it in and
  /// writes it to the database.
  Future<void> upsertSegment(String meetingId, Segment segment) async {
    if (segment.isFinal) await _db.upsertSegment(meetingId, segment);
    _replace(meetingId, (meeting) {
      final segments = [...meeting.segments];
      final index = segments.indexWhere((s) => s.id == segment.id);
      if (index >= 0) {
        segments[index] = segment;
      } else {
        segments.add(segment);
      }
      return meeting.copyWith(segments: segments);
    });
  }

  Future<void> setAudioPath(String meetingId, String audioPath) async {
    await _db.setAudioPath(meetingId, audioPath);
    _replace(meetingId, (m) => m.copyWith(audioPath: audioPath));
  }

  Future<void> deleteAudio(String meetingId) async {
    final path = byId(meetingId)?.audioPath;
    if (path != null) await _deleteFile(path);
    await _db.setAudioPath(meetingId, null);
    _replace(meetingId, (m) => m.copyWith(clearAudioPath: true));
  }

  Future<void> replaceSegments(
    String meetingId,
    List<Segment> segments, {
    required TranscriptSource source,
  }) async {
    await _db.replaceSegments(meetingId, segments, source: source);
    _replace(
      meetingId,
      (m) => m.copyWith(segments: segments, transcriptSource: source),
    );
  }

  /// Drops any trailing partial (never persisted) and stamps the end time.
  Future<void> stopMeeting(String meetingId) async {
    final endedAt = DateTime.now();
    await _db.stopMeeting(meetingId, endedAt);
    _replace(
      meetingId,
      (m) => m.copyWith(endedAt: endedAt, segments: m.finalSegments),
    );
  }

  Future<void> addAnalysis(String meetingId, Analysis analysis) async {
    await _db.insertAnalysis(meetingId, analysis);
    _replace(meetingId, (m) => m.copyWith(analyses: [...m.analyses, analysis]));
  }

  Future<void> rename(String meetingId, String newTitle) async {
    await _db.renameMeeting(meetingId, newTitle);
    _replace(meetingId, (m) => m.copyWith(title: newTitle));
  }

  Future<void> delete(String meetingId) async {
    await deleteAudio(meetingId);
    await _db.deleteMeeting(meetingId);
    state = AsyncData(
      (state.value ?? const <Meeting>[])
          .where((m) => m.id != meetingId)
          .toList(),
    );
  }
}

final meetingsProvider = AsyncNotifierProvider<MeetingsNotifier, List<Meeting>>(
  MeetingsNotifier.new,
);
