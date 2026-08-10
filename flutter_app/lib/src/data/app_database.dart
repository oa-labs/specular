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
  TextColumn get summary => text().nullable()();
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

  /// Test seam for exercising the shared schema without platform plugins.
  factory AppDatabase.forTesting(QueryExecutor executor) =>
      AppDatabase._(executor);

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
  int get schemaVersion => 8;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      // Search uses LIKE. The Android migration rebuilds old Room FTS4 indexes
      // because Flutter's bundled SQLite intentionally does not include FTS4.
    },
    onUpgrade: (m, from, to) async {
      if (from < 8) {
        await m.renameColumn(noteRows, 'snippet', noteRows.summary);
      }
    },
  );
}
