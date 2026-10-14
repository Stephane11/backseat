import 'package:drift/drift.dart';

@DataClassName('MeetingsTableData')
class Meetings extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get contextNote => text().nullable()();

  /// JSON-encoded list of per-meeting vocabulary terms (schema v2).
  TextColumn get extraTerms => text().nullable()();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get endedAt => dateTime().nullable()();
  TextColumn get audioPath => text().nullable()();
  TextColumn get transcriptSource =>
      text().withDefault(const Constant('live'))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('SegmentsTableData')
class Segments extends Table {
  TextColumn get id => text()();
  TextColumn get meetingId => text().references(Meetings, #id)();
  IntColumn get startMs => integer()();
  IntColumn get endMs => integer()();
  TextColumn get content => text().named('text')();
  BoolColumn get isFinal => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('AnalysesTableData')
class Analyses extends Table {
  TextColumn get id => text()();
  TextColumn get meetingId => text().references(Meetings, #id)();
  DateTimeColumn get createdAt => dateTime()();
  TextColumn get model => text()();
  IntColumn get transcriptUpToMs => integer()();
  TextColumn get summary => text()();
  TextColumn get itemsJson => text()();

  @override
  Set<Column> get primaryKey => {id};
}

class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}
