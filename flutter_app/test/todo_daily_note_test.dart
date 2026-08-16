import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:specular/src/data/app_database.dart';
import 'package:specular/src/data/note_repository.dart';
import 'package:specular/src/domain/note.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('appends a new to-do to today\'s daily note', () async {
    final root = await Directory.systemTemp.createTemp('specular-todo-test-');
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(() async {
      await database.close();
      await root.delete(recursive: true);
    });
    final repository = NoteRepository(
      database,
      Directory('${root.path}/notes'),
    );

    final daily = await repository.appendToToday('- [ ] Buy milk');

    expect(daily.isDaily, isTrue);
    expect(daily.path, startsWith('daily/'));
    expect(daily.body, contains('- [ ] Buy milk'));
    expect(
      (await repository.watchNotes().first).where((note) => !note.isDaily),
      isEmpty,
    );
  });

  test('schedules a task and streams it as a daily-note backlink', () async {
    final root = await Directory.systemTemp.createTemp(
      'specular-schedule-test-',
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
    final source = await repository.create(
      title: 'Planning',
      body: '+ [ ] Refine estimation logic',
    );
    final date = DateTime(2026, 8, 18);

    await repository.scheduleGlobalTask(
      noteId: source.id,
      taskIndex: 0,
      date: date,
    );

    final updated = await repository.get(source.id);
    final daily = await repository.findByPath('daily/2026-08-18.md');
    expect(
      updated!.body,
      contains('+ [ ] Refine estimation logic [[2026-08-18]]'),
    );
    expect(daily, isNotNull);
    final dailyNote = daily!;
    final resolvedDaily = await repository.findByWikiLinkTitle('2026-08-18');
    expect(resolvedDaily, isNotNull);
    expect(resolvedDaily!.id, dailyNote.id);

    final backlinks = await repository
        .watchScheduledTaskBacklinks(dailyNote)
        .first;
    expect(backlinks, hasLength(1));
    expect(backlinks.single.sourceNoteTitle, 'Planning');
    expect(backlinks.single.text, contains('Refine estimation logic'));
    expect(backlinks.single.isCompleted, isFalse);

    await repository.updateTodoText(
      TodoItem(
        noteId: backlinks.single.sourceNoteId,
        taskIndex: backlinks.single.taskIndex,
        text: backlinks.single.text,
        isCompleted: backlinks.single.isCompleted,
        noteTitle: backlinks.single.sourceNoteTitle,
      ),
      'Refine estimation logic after review',
    );
    expect(
      (await repository.get(source.id))!.body,
      contains('Refine estimation logic after review [[2026-08-18]]'),
    );

    await repository.toggleTodo(
      TodoItem(
        noteId: backlinks.single.sourceNoteId,
        taskIndex: backlinks.single.taskIndex,
        text: backlinks.single.text,
        isCompleted: backlinks.single.isCompleted,
        noteTitle: backlinks.single.sourceNoteTitle,
      ),
    );
    final completed = await repository
        .watchScheduledTaskBacklinks(dailyNote)
        .first;
    expect(completed.single.isCompleted, isTrue);
  });
}
