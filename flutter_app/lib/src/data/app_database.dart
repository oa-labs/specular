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

  /// Incremented for every local mutation.  Remote acknowledgements must only
  /// clear dirty state when they acknowledge this exact revision.
  IntColumn get localRevision =>
      integer().named('localRevision').withDefault(const Constant(0))();
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

/// Durable, rebuildable incoming-link index. Targets are stable note ids;
/// source Markdown remains canonical and can always regenerate this table.
class LinkEntries extends Table {
  @override
  String get tableName => 'link_index';

  TextColumn get sourceNoteId => text().named('sourceNoteId')();
  IntColumn get linkIndex => integer().named('linkIndex')();
  TextColumn get targetNoteId => text().named('targetNoteId')();
  TextColumn get kind => text()();
  TextColumn get label => text()();
  @override
  Set<Column<Object>> get primaryKey => {sourceNoteId, linkIndex};
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

/// A durable audit of local mutations.  The current note row is the compact
/// materialized state, while this journal lets a crash between local work and
/// a remote commit be recovered without guessing intent.
class SyncOperations extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get noteId => text().nullable()();
  TextColumn get kind => text()();
  TextColumn get path => text()();
  TextColumn get fromPath => text().nullable()();
  IntColumn get localRevision => integer()();
  IntColumn get createdAt => integer()();
}

/// A database-backed lease shared by the UI isolate and WorkManager isolates.
/// It intentionally has an expiry so a killed worker cannot wedge sync.
class SyncLeases extends Table {
  TextColumn get scope => text()();
  TextColumn get owner => text()();
  IntColumn get expiresAt => integer().named('expiresAt')();
  @override
  Set<Column<Object>> get primaryKey => {scope};
}

@DriftDatabase(
  tables: [
    NoteRows,
    TodoEntries,
    TodoIndexStates,
    LinkEntries,
    Attachments,
    SyncOperations,
    SyncLeases,
  ],
)
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
  int get schemaVersion => 11;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await ensureUniqueNotePaths();
      // Search uses LIKE. The Android migration rebuilds old Room FTS4 indexes
      // because Flutter's bundled SQLite intentionally does not include FTS4.
    },
    onUpgrade: (m, from, to) async {
      if (from < 8) {
        await m.renameColumn(noteRows, 'snippet', noteRows.summary);
      }
      if (from < 9) await ensureUniqueNotePaths();
      if (from < 10) {
        await m.addColumn(noteRows, noteRows.localRevision);
        await m.createTable(syncOperations);
        await m.createTable(syncLeases);
      }
      if (from < 11) await m.createTable(linkEntries);
    },
  );

  /// Repairs duplicate paths left by older conflict handling, preserving every
  /// note as a separately syncable recovered conflict before enforcing the
  /// path uniqueness that sync depends on.
  Future<void> ensureUniqueNotePaths() async {
    await transaction(() async {
      final duplicatePaths = await customSelect(
        'SELECT path FROM notes GROUP BY path HAVING COUNT(*) > 1',
      ).get();
      final occupiedPaths = (await customSelect(
        'SELECT path FROM notes',
      ).get()).map((row) => row.read<String>('path')).toSet();

      for (final row in duplicatePaths) {
        final path = row.read<String>('path');
        final notesAtPath = await customSelect(
          '''
            SELECT id FROM notes
            WHERE path = ?
            ORDER BY isConflict ASC, updatedAt DESC, id ASC
          ''',
          variables: [Variable.withString(path)],
        ).get();
        for (final duplicate in notesAtPath.skip(1)) {
          final recoveredPath = _recoveredPath(path, occupiedPaths);
          occupiedPaths.add(recoveredPath);
          await customStatement(
            '''
              UPDATE notes
              SET path = ?,
                  title = title || ' (recovered)',
                  lastRemoteSha = NULL,
                  isDirty = 1,
                  isPendingDeletion = 0,
                  pendingRenameFromPath = NULL,
                  pendingRenameFromSha = NULL,
                  isConflict = 1
              WHERE id = ?
            ''',
            [recoveredPath, duplicate.read<String>('id')],
          );
        }
      }
      await customStatement(
        'CREATE UNIQUE INDEX IF NOT EXISTS notes_path_unique ON notes(path)',
      );
    });
  }

  String _recoveredPath(String path, Set<String> occupiedPaths) {
    final extensionStart = path.lastIndexOf('.');
    final base = extensionStart == -1
        ? path
        : path.substring(0, extensionStart);
    final extension = extensionStart == -1
        ? ''
        : path.substring(extensionStart);
    for (var index = 2; ; index++) {
      final candidate = '$base (recovered $index)$extension';
      if (!occupiedPaths.contains(candidate)) return candidate;
    }
  }
}
