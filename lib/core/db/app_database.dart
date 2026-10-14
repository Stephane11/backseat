import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../models/analysis.dart';
import '../models/meeting.dart';
import '../models/segment.dart';
import 'tables.dart';

part 'app_database.g.dart';

@DriftDatabase(tables: [Meetings, Segments, Analyses, Settings])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());
  AppDatabase.forTesting(super.connection);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.addColumn(meetings, meetings.extraTerms);
      }
    },
  );

  Future<List<Meeting>> loadAllMeetings() async {
    final meetingRows = await select(meetings).get();
    final result = <Meeting>[];
    for (final row in meetingRows) {
      result.add(await _hydrate(row));
    }
    return result;
  }

  Future<Meeting> _hydrate(MeetingsTableData row) async {
    final segmentRows =
        await (select(segments)
              ..where((s) => s.meetingId.equals(row.id))
              ..orderBy([(s) => OrderingTerm.asc(s.startMs)]))
            .get();
    final analysisRows =
        await (select(analyses)
              ..where((a) => a.meetingId.equals(row.id))
              ..orderBy([(a) => OrderingTerm.asc(a.createdAt)]))
            .get();

    return Meeting(
      id: row.id,
      title: row.title,
      contextNote: row.contextNote,
      extraTerms: row.extraTerms == null
          ? const []
          : (jsonDecode(row.extraTerms!) as List<dynamic>).cast<String>(),
      startedAt: row.startedAt,
      endedAt: row.endedAt,
      audioPath: row.audioPath,
      transcriptSource: row.transcriptSource == 'finalPass'
          ? TranscriptSource.finalPass
          : TranscriptSource.live,
      segments: segmentRows
          .map(
            (s) => Segment(
              id: s.id,
              start: Duration(milliseconds: s.startMs),
              end: Duration(milliseconds: s.endMs),
              text: s.content,
              isFinal: s.isFinal,
            ),
          )
          .toList(),
      analyses: analysisRows
          .map(
            (a) => Analysis(
              id: a.id,
              createdAt: a.createdAt,
              model: a.model,
              transcriptUpTo: Duration(milliseconds: a.transcriptUpToMs),
              summary: a.summary,
              items: decodeAnalysisItems(a.itemsJson),
            ),
          )
          .toList(),
    );
  }

  Future<void> insertMeeting(Meeting meeting) {
    return into(meetings).insert(
      MeetingsCompanion.insert(
        id: meeting.id,
        title: meeting.title,
        contextNote: Value(meeting.contextNote),
        extraTerms: Value(
          meeting.extraTerms.isEmpty ? null : jsonEncode(meeting.extraTerms),
        ),
        startedAt: meeting.startedAt,
        audioPath: Value(meeting.audioPath),
        transcriptSource: Value(meeting.transcriptSource.name),
      ),
    );
  }

  Future<void> upsertSegment(String meetingId, Segment segment) {
    return into(segments).insertOnConflictUpdate(
      SegmentsCompanion.insert(
        id: segment.id,
        meetingId: meetingId,
        startMs: segment.start.inMilliseconds,
        endMs: segment.end.inMilliseconds,
        content: segment.text,
        isFinal: Value(segment.isFinal),
      ),
    );
  }

  /// Swaps the live draft for the Whisper final pass in one transaction, so a
  /// crash mid-way never leaves a half-replaced transcript.
  Future<void> replaceSegments(
    String meetingId,
    List<Segment> newSegments, {
    required TranscriptSource source,
  }) {
    return transaction(() async {
      await (delete(
        segments,
      )..where((s) => s.meetingId.equals(meetingId))).go();
      for (final segment in newSegments) {
        await upsertSegment(meetingId, segment);
      }
      await (update(meetings)..where((m) => m.id.equals(meetingId))).write(
        MeetingsCompanion(transcriptSource: Value(source.name)),
      );
    });
  }

  Future<void> stopMeeting(String meetingId, DateTime endedAt) {
    return (update(meetings)..where((m) => m.id.equals(meetingId))).write(
      MeetingsCompanion(endedAt: Value(endedAt)),
    );
  }

  Future<void> setAudioPath(String meetingId, String? audioPath) {
    return (update(meetings)..where((m) => m.id.equals(meetingId))).write(
      MeetingsCompanion(audioPath: Value(audioPath)),
    );
  }

  Future<void> insertAnalysis(String meetingId, Analysis analysis) {
    return into(analyses).insert(
      AnalysesCompanion.insert(
        id: analysis.id,
        meetingId: meetingId,
        createdAt: analysis.createdAt,
        model: analysis.model,
        transcriptUpToMs: analysis.transcriptUpTo.inMilliseconds,
        summary: analysis.summary,
        itemsJson: encodeAnalysisItems(analysis.items),
      ),
    );
  }

  Future<void> renameMeeting(String id, String title) {
    return (update(meetings)..where((m) => m.id.equals(id))).write(
      MeetingsCompanion(title: Value(title)),
    );
  }

  Future<void> deleteMeeting(String id) {
    return transaction(() async {
      await (delete(segments)..where((s) => s.meetingId.equals(id))).go();
      await (delete(analyses)..where((a) => a.meetingId.equals(id))).go();
      await (delete(meetings)..where((m) => m.id.equals(id))).go();
    });
  }

  Future<String?> getSetting(String key) async {
    final row = await (select(
      settings,
    )..where((s) => s.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<void> putSetting(String key, String value) {
    return into(
      settings,
    ).insertOnConflictUpdate(SettingsCompanion.insert(key: key, value: value));
  }
}

QueryExecutor _openConnection() {
  return driftDatabase(
    name: 'backseat',
    native: DriftNativeOptions(
      databaseDirectory: getApplicationSupportDirectory,
    ),
  );
}
