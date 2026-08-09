import 'dart:io';

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
        snippet TEXT,
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
}
