import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../platform/legacy_bridge.dart';

part 'app_database.g.dart';

class NoteRows extends Table {
  @override
  String get tableName => 'notes';

  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get path => text()();
  TextColumn get rawMarkdown => text().named('rawMarkdown')();
  TextColumn get body => text()();
  TextColumn get aliases => text()();
  TextColumn get snippet => text().nullable()();
  BoolColumn get isDaily => boolean().named('isDaily')();
  BoolColumn get isPinned =>
      boolean().named('isPinned').withDefault(const Constant(false))();
  TextColumn get lastRemoteSha => text().named('lastRemoteSha').nullable()();
  BoolColumn get isDirty =>
      boolean().named('isDirty').withDefault(const Constant(false))();
  BoolColumn get isPendingDeletion =>
      boolean().named('isPendingDeletion').withDefault(const Constant(false))();
  TextColumn get pendingRenameFromPath =>
      text().named('pendingRenameFromPath').nullable()();
  TextColumn get pendingRenameFromSha =>
      text().named('pendingRenameFromSha').nullable()();
  BoolColumn get isConflict =>
      boolean().named('isConflict').withDefault(const Constant(false))();
  IntColumn get updatedAt => integer().named('updatedAt')();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

class TodoEntries extends Table {
  @override
  String get tableName => 'todo_index';

  TextColumn get noteId => text().named('noteId')();
  IntColumn get taskIndex => integer().named('taskIndex')();
  TextColumn get taskText => text().named('text')();
  BoolColumn get isCompleted => boolean().named('isCompleted')();
  @override
  Set<Column<Object>> get primaryKey => {noteId, taskIndex};
}

class TodoIndexStates extends Table {
  @override
  String get tableName => 'todo_index_state';

  IntColumn get id => integer().withDefault(const Constant(0))();
  BoolColumn get isReady =>
      boolean().named('isReady').withDefault(const Constant(false))();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Attachments extends Table {
  @override
  String get tableName => 'attachments';

  TextColumn get path => text()();
  TextColumn get mimeType => text().named('mimeType').nullable()();
  TextColumn get lastRemoteSha => text().named('lastRemoteSha').nullable()();
  BoolColumn get isDirty => boolean().named('isDirty')();
  IntColumn get updatedAt => integer().named('updatedAt')();
  @override
  Set<Column<Object>> get primaryKey => {path};
}

@DriftDatabase(tables: [NoteRows, TodoEntries, TodoIndexStates, Attachments])
class AppDatabase extends _$AppDatabase {
  AppDatabase._(super.executor);

  factory AppDatabase.openLegacy(LegacyState state) => AppDatabase._(
    driftDatabase(
      name: 'reflect',
      native: DriftNativeOptions(
        databasePath: () async => state.databasePath,
        shareAcrossIsolates: true,
      ),
    ),
  );

  @override
  int get schemaVersion => 7;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      // Fresh installs use LIKE search until they receive their first sync.
      // Existing Room databases retain their FTS4 table and triggers intact.
    },
  );
}
