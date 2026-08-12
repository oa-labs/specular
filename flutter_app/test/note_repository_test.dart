import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:specular/src/data/app_database.dart';
import 'package:specular/src/data/note_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('creates regular and daily notes in a Kotlin-style schema', () async {
    final root = await Directory.systemTemp.createTemp('specular-notes-test-');
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(() async {
      await database.close();
      await root.delete(recursive: true);
    });

    // Room's fresh schema does not guarantee Drift's Dart-side defaults. This
    // reproduces the required status columns without SQL DEFAULT clauses.
    await database.customStatement('DROP TABLE notes');
    await database.customStatement('''
      CREATE TABLE notes (
        id TEXT NOT NULL PRIMARY KEY,
        title TEXT NOT NULL,
        path TEXT NOT NULL,
        rawMarkdown TEXT NOT NULL,
        body TEXT NOT NULL,
        aliases TEXT NOT NULL,
        summary TEXT,
        isDaily INTEGER NOT NULL,
        isPinned INTEGER NOT NULL,
        lastRemoteSha TEXT,
        isDirty INTEGER NOT NULL,
        isPendingDeletion INTEGER NOT NULL,
        pendingRenameFromPath TEXT,
        pendingRenameFromSha TEXT,
        isConflict INTEGER NOT NULL,
        localRevision INTEGER NOT NULL DEFAULT 0,
        updatedAt INTEGER NOT NULL
      )
    ''');

    final repository = NoteRepository(
      database,
      Directory('${root.path}/notes'),
    );
    final regular = await repository.create(title: 'Regular');
    final daily = await repository.getOrCreateToday();

    expect(regular.isDaily, isFalse);
    expect(daily.isDaily, isTrue);
    expect(daily.path, startsWith('daily/'));
  });

  test('removes a clean note deleted remotely', () async {
    final root = await Directory.systemTemp.createTemp('specular-notes-test-');
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(() async {
      await database.close();
      await root.delete(recursive: true);
    });
    final repository = NoteRepository(
      database,
      Directory('${root.path}/notes'),
    );
    final note = await repository.create(title: 'Removed remotely');
    await repository.markSynced(note, 'remote-sha');

    await repository.reconcileRemoteRemovals({});

    expect(await repository.get(note.id), isNull);
    expect(await File('${root.path}/notes/${note.path}').exists(), isFalse);
  });

  test('removes a clean conflict copy deleted remotely', () async {
    final root = await Directory.systemTemp.createTemp('specular-notes-test-');
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(() async {
      await database.close();
      await root.delete(recursive: true);
    });
    final repository = NoteRepository(
      database,
      Directory('${root.path}/notes'),
    );
    final note = await repository.create(title: 'Original');
    await repository.preserveConflict(note);
    final conflict = (await repository.watchNotes().first).singleWhere(
      (candidate) => candidate.isConflict,
    );
    await repository.markSynced(conflict, 'remote-conflict-sha');

    await repository.reconcileRemoteRemoval(conflict.path);

    expect(await repository.get(conflict.id), isNull);
  });

  test('clears the local mirror, index, and pending sync state', () async {
    final root = await Directory.systemTemp.createTemp('specular-notes-test-');
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(() async {
      await database.close();
      await root.delete(recursive: true);
    });
    final notesRoot = Directory('${root.path}/notes');
    final repository = NoteRepository(database, notesRoot);
    final note = await repository.create(title: 'Only local');

    expect(await repository.hasPendingSyncChanges(), isTrue);
    expect(await File('${notesRoot.path}/${note.path}').exists(), isTrue);

    await repository.clearLocalCache();

    expect(await repository.hasLocalNotes(), isFalse);
    expect(await repository.hasPendingSyncChanges(), isFalse);
    expect(await notesRoot.list().toList(), isEmpty);
    expect(await database.select(database.syncOperations).get(), isEmpty);
  });

  test('does not use a note body as a missing metadata summary', () async {
    final root = await Directory.systemTemp.createTemp('specular-notes-test-');
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(() async {
      await database.close();
      await root.delete(recursive: true);
    });
    final repository = NoteRepository(
      database,
      Directory('${root.path}/notes'),
    );

    await repository.applyRemote(
      path: 'notes/no-summary.md',
      sha: 'remote-sha',
      raw: '# No summary\n\nThis note has no frontmatter summary.\n',
    );

    final note = await repository.findByPath('notes/no-summary.md');
    expect(note?.summary, isNull);
  });

  test('preserves a locally edited remote deletion as a conflict', () async {
    final root = await Directory.systemTemp.createTemp('specular-notes-test-');
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(() async {
      await database.close();
      await root.delete(recursive: true);
    });
    final repository = NoteRepository(
      database,
      Directory('${root.path}/notes'),
    );
    final created = await repository.create(title: 'Edited locally');
    await repository.markSynced(created, 'remote-sha');
    final synced = (await repository.get(created.id))!;
    await repository.save(
      synced,
      title: synced.title,
      body: '# Edited locally\n\nLocal edit',
    );

    await repository.reconcileRemoteRemovals({});

    final notes = await repository.watchNotes().first;
    expect(notes, hasLength(1));
    expect(notes.single.isConflict, isTrue);
    expect(notes.single.isDirty, isTrue);
    expect(notes.single.title, 'Edited locally (conflict)');
  });

  test('gives same-day conflict copies unique paths', () async {
    final root = await Directory.systemTemp.createTemp('specular-notes-test-');
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(() async {
      await database.close();
      await root.delete(recursive: true);
    });
    final repository = NoteRepository(
      database,
      Directory('${root.path}/notes'),
    );
    final note = await repository.create(title: 'Edited locally');

    await repository.preserveConflict(note);
    await repository.preserveConflict(note);

    final conflicts = (await repository.watchNotes().first)
        .where((note) => note.isConflict)
        .toList();
    expect(conflicts.map((note) => note.path).toSet(), hasLength(2));
    expect(conflicts.map((note) => note.path), contains(endsWith(' 2.md')));
  });

  test('repairs duplicate note paths during the database migration', () async {
    final root = await Directory.systemTemp.createTemp('specular-notes-test-');
    final databaseFile = File('${root.path}/reflect.db');
    addTearDown(() => root.delete(recursive: true));
    final legacyDatabase = AppDatabase.forTesting(
      NativeDatabase(databaseFile, enableMigrations: false),
    );
    await legacyDatabase.customStatement('''
      CREATE TABLE notes (
        id TEXT NOT NULL PRIMARY KEY,
        title TEXT NOT NULL,
        path TEXT NOT NULL,
        rawMarkdown TEXT NOT NULL,
        body TEXT NOT NULL,
        aliases TEXT NOT NULL,
        summary TEXT,
        isDaily INTEGER NOT NULL,
        isPinned INTEGER NOT NULL,
        lastRemoteSha TEXT,
        isDirty INTEGER NOT NULL,
        isPendingDeletion INTEGER NOT NULL,
        pendingRenameFromPath TEXT,
        pendingRenameFromSha TEXT,
        isConflict INTEGER NOT NULL,
        updatedAt INTEGER NOT NULL
      )
    ''');
    await legacyDatabase.customStatement('PRAGMA user_version = 8');
    for (final id in ['first', 'second']) {
      await legacyDatabase
          .into(legacyDatabase.noteRows)
          .insert(
            NoteRowsCompanion.insert(
              id: id,
              title: 'Duplicate',
              path: 'notes/duplicate.md',
              rawMarkdown: '# Duplicate',
              body: '# Duplicate',
              aliases: '[]',
              isDaily: false,
              isPinned: const Value(false),
              lastRemoteSha: const Value('remote-sha'),
              isDirty: const Value(false),
              isPendingDeletion: const Value(false),
              isConflict: const Value(false),
              updatedAt: id == 'first' ? 1 : 2,
            ),
          );
    }
    await legacyDatabase.close();

    final database = AppDatabase.forTesting(NativeDatabase(databaseFile));
    addTearDown(database.close);

    final notes = await database.select(database.noteRows).get();
    expect(notes, hasLength(2));
    expect(notes.map((note) => note.path).toSet(), hasLength(2));
    expect(
      notes.where((note) => note.path == 'notes/duplicate.md'),
      hasLength(1),
    );
    final recovered = notes.singleWhere(
      (note) => note.path != 'notes/duplicate.md',
    );
    expect(recovered.path, 'notes/duplicate (recovered 2).md');
    expect(recovered.isConflict, isTrue);
    expect(recovered.isDirty, isTrue);
    expect(recovered.lastRemoteSha, isNull);
  });

  test('does not treat an unsynced note as a remote deletion', () async {
    final root = await Directory.systemTemp.createTemp('specular-notes-test-');
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(() async {
      await database.close();
      await root.delete(recursive: true);
    });
    final repository = NoteRepository(
      database,
      Directory('${root.path}/notes'),
    );
    final note = await repository.create(title: 'Offline note');

    await repository.reconcileRemoteRemovals({});

    expect(await repository.get(note.id), isNotNull);
  });

  test('pins and unpins locally without creating a sync change', () async {
    final root = await Directory.systemTemp.createTemp('specular-notes-test-');
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(() async {
      await database.close();
      await root.delete(recursive: true);
    });
    final repository = NoteRepository(
      database,
      Directory('${root.path}/notes'),
    );
    final note = await repository.create(title: 'Pin me');
    await repository.markSynced(note, 'remote-sha');

    await repository.setPinned(note, true);
    final pinned = (await repository.get(note.id))!;
    expect(pinned.isPinned, isTrue);
    expect(pinned.isDirty, isFalse);

    await repository.setPinned(pinned, false);
    expect((await repository.get(note.id))!.isPinned, isFalse);
  });

  test(
    'keeps an edit made during an in-flight acknowledgement dirty',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'specular-notes-test-',
      );
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(() async {
        await database.close();
        await root.delete(recursive: true);
      });
      final repository = NoteRepository(
        database,
        Directory('${root.path}/notes'),
      );
      final created = await repository.create(title: 'Race safe');
      await repository.markSynced(created, 'sha-1');
      final saved = await repository.save(
        (await repository.get(created.id))!,
        title: 'Race safe',
        body: '# Race safe\n\nNew local content',
      );

      // This is the acknowledgement for the earlier revision, received after
      // the new save. It must establish a new base SHA but never clear dirty.
      await repository.acknowledgeNotesSynced({
        saved.id: (revision: created.localRevision, sha: 'sha-2'),
      });

      final current = (await repository.get(saved.id))!;
      expect(current.localRevision, greaterThan(created.localRevision));
      expect(current.isDirty, isTrue);
      expect(current.lastRemoteSha, 'sha-2');
      final operations = await database.select(database.syncOperations).get();
      expect(
        operations.any(
          (operation) => operation.localRevision == current.localRevision,
        ),
        isTrue,
      );
    },
  );

  test('uses a database lease across repository instances', () async {
    final root = await Directory.systemTemp.createTemp('specular-notes-test-');
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(() async {
      await database.close();
      await root.delete(recursive: true);
    });
    final repository = NoteRepository(
      database,
      Directory('${root.path}/notes'),
    );
    final first = await repository.acquireSyncLease(owner: 'worker-a');
    expect(first, isNotNull);
    expect(await repository.isGitHubSyncActive(), isTrue);
    expect(await repository.acquireSyncLease(owner: 'worker-b'), isNull);

    await repository.releaseSyncLease(first!);
    expect(await repository.isGitHubSyncActive(), isFalse);
    expect(await repository.acquireSyncLease(owner: 'worker-b'), isNotNull);
  });

  test('rename and delete intent survives a process restart', () async {
    final root = await Directory.systemTemp.createTemp('specular-notes-test-');
    final databaseFile = File('${root.path}/reflect.db');
    addTearDown(() => root.delete(recursive: true));
    final firstDatabase = AppDatabase.forTesting(NativeDatabase(databaseFile));
    final firstRepository = NoteRepository(
      firstDatabase,
      Directory('${root.path}/notes'),
    );
    final created = await firstRepository.create(title: 'Restart me');
    await firstRepository.markSynced(created, 'remote-sha');
    final renamed = await firstRepository.rename(
      (await firstRepository.get(created.id))!,
      'archive/restart-me.md',
    );
    await firstRepository.delete(renamed);
    await firstDatabase.close();

    final restarted = AppDatabase.forTesting(NativeDatabase(databaseFile));
    addTearDown(restarted.close);
    final recovered = await (restarted.select(
      restarted.noteRows,
    )..where((row) => row.id.equals(created.id))).getSingle();
    final operations = await restarted.select(restarted.syncOperations).get();

    expect(recovered.isPendingDeletion, isTrue);
    expect(recovered.pendingRenameFromPath, created.path);
    expect(
      operations.map((operation) => operation.kind),
      containsAll(['rename', 'delete']),
    );
  });

  test(
    'archives a note directly in the repository-root archive folder',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'specular-notes-test-',
      );
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(() async {
        await database.close();
        await root.delete(recursive: true);
      });
      final repository = NoteRepository(
        database,
        Directory('${root.path}/notes'),
      );
      final created = await repository.create(
        title: 'Project plan',
        body: '[Research](../../notes/research.md)',
        folder: 'projects/alpha',
      );
      await repository.create(title: 'Research', folder: 'notes');
      final daily = await repository.createDaily(
        'daily/2026-08-09.md',
        'Daily',
      );
      await repository.save(
        daily,
        title: daily.title,
        body:
            '${daily.body.trimRight()}\n\n[Plan](../projects/alpha/project-plan.md)\n',
      );
      await repository.markSynced(created, 'remote-sha');

      final archived = await repository.archive(
        (await repository.get(created.id))!,
      );

      expect(archived.path, 'archive/project-plan.md');
      expect(archived.body, contains('[Research](../notes/research.md)'));
      expect(archived.pendingRenameFromPath, 'projects/alpha/project-plan.md');
      expect(archived.pendingRenameFromSha, 'remote-sha');
      expect(
        await File(
          '${root.path}/notes/projects/alpha/project-plan.md',
        ).exists(),
        isFalse,
      );
      expect(
        await File('${root.path}/notes/archive/project-plan.md').exists(),
        isTrue,
      );
      expect(
        (await repository.findByPath('daily/2026-08-09.md'))!.body,
        contains('[Plan](../archive/project-plan.md)'),
      );
    },
  );

  test('preserves links when sync detects a manually moved note', () async {
    final root = await Directory.systemTemp.createTemp('specular-notes-test-');
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(() async {
      await database.close();
      await root.delete(recursive: true);
    });
    final repository = NoteRepository(
      database,
      Directory('${root.path}/notes'),
    );
    final project = await repository.create(
      title: 'Project plan',
      body: '[Research](../../notes/research.md)',
      folder: 'projects/alpha',
    );
    await repository.create(title: 'Research', folder: 'notes');
    final daily = await repository.createDaily('daily/2026-08-09.md', 'Daily');
    await repository.save(
      daily,
      title: daily.title,
      body:
          '${daily.body.trimRight()}\n\n[Plan](../projects/alpha/project-plan.md)\n',
    );

    await repository.applyRemote(
      path: 'archive/project-plan.md',
      sha: 'remote-sha',
      raw: project.rawMarkdown,
    );

    expect(
      (await repository.findByPath('archive/project-plan.md'))!.body,
      contains('[Research](../notes/research.md)'),
    );
    expect(
      (await repository.findByPath('daily/2026-08-09.md'))!.body,
      contains('[Plan](../archive/project-plan.md)'),
    );
  });

  test('indexes and toggles only Reflect global plus tasks', () async {
    final root = await Directory.systemTemp.createTemp('specular-notes-test-');
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(() async {
      await database.close();
      await root.delete(recursive: true);
    });
    final repository = NoteRepository(
      database,
      Directory('${root.path}/notes'),
    );
    final note = await repository.create(
      title: 'Task scopes',
      body: '+ [ ] Global task\n- [ ] Local checkbox',
    );

    final todos = await repository.watchTodos().first;
    expect(todos.map((todo) => todo.text), ['Global task']);

    await repository.toggleTodo(todos.single);
    expect(
      (await repository.get(note.id))!.body,
      contains('+ [x] Global task\n- [ ] Local checkbox'),
    );
  });
}
