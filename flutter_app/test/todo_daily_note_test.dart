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

  test('schedules a task without creating a blank daily note', () async {
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
    expect(daily, isNull);
    final resolvedDaily = await repository.findByWikiLinkTitle('2026-08-18');
    expect(resolvedDaily, isNull);

    final backlinks = await repository
        .watchScheduledTaskBacklinksForDate(DateTime(2026, 8, 18))
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
        .watchScheduledTaskBacklinksForDate(DateTime(2026, 8, 18))
        .first;
    expect(completed.single.isCompleted, isTrue);
  });

  test(
    'recurring emoji-dated tasks do not create the next daily file',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'specular-recurring-todo-test-',
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
        title: 'Household',
        body: '+ [ ] Water plants 📅 2026-06-01 🔁 every day',
      );
      final firstDaily = await repository.getOrCreateDaily(
        DateTime(2026, 6, 1),
      );

      // Note-preview checkboxes use the mixed checkbox index, not the To-dos
      // screen's global-task index. Recurrence must behave identically here.
      await repository.toggleCheckbox(noteId: source.id, taskIndex: 0);

      expect(
        (await repository.get(source.id))!.body,
        contains(
          '+ [x] Water plants 📅 2026-06-01 🔁 every day\n'
          '+ [ ] Water plants 🔁 every day 📅 2026-06-02',
        ),
      );
      expect(
        await repository.watchScheduledTaskBacklinks(firstDaily).first,
        predicate<List<ScheduledTaskBacklink>>(
          (backlinks) => backlinks.length == 1 && backlinks.single.isCompleted,
        ),
      );
      final nextDaily = await repository.findByPath('daily/2026-06-02.md');
      expect(nextDaily, isNull);
      final backlinks = await repository
          .watchScheduledTaskBacklinksForDate(DateTime(2026, 6, 2))
          .first;
      expect(backlinks.single.text, contains('📅 2026-06-02'));
      expect(backlinks.single.isCompleted, isFalse);
    },
  );

  test(
    'daily files are created only for meaningful content and removed when cleared',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'specular-daily-test-',
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
      final date = DateTime(2026, 8, 16);

      expect(await repository.saveDailyContent(date, '  \n '), isNull);
      expect(await repository.findDaily(date), isNull);
      expect(
        await File('${root.path}/notes/daily/2026-08-16.md').exists(),
        isFalse,
      );

      final created = await repository.saveDailyContent(date, 'Daily thought');
      expect(created, isNotNull);
      expect(created!.path, 'daily/2026-08-16.md');
      expect(created.body, contains('Daily thought'));
      expect(
        await File('${root.path}/notes/daily/2026-08-16.md').exists(),
        isTrue,
      );

      expect(await repository.saveDailyContent(date, ''), isNull);
      expect(await repository.findDaily(date), isNull);
      expect(
        await File('${root.path}/notes/daily/2026-08-16.md').exists(),
        isFalse,
      );
    },
  );
}
