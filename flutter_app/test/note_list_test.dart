import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:specular/src/domain/note.dart';
import 'package:specular/src/sync/github_sync.dart';
import 'package:specular/src/ui/specular_app.dart';
import 'package:specular/src/ui/screens.dart';

void main() {
  Note note(
    String title,
    int updatedAt, {
    String? path,
    bool pinned = false,
    String body = '',
  }) => Note(
    id: title,
    title: title,
    path: path ?? '$title.md',
    rawMarkdown: '',
    body: body,
    summary: null,
    aliases: const [],
    isDaily: false,
    isPinned: pinned,
    lastRemoteSha: null,
    isDirty: false,
    isPendingDeletion: false,
    pendingRenameFromPath: null,
    pendingRenameFromSha: null,
    isConflict: false,
    updatedAt: DateTime.fromMillisecondsSinceEpoch(updatedAt),
  );

  test('retains the selected home view outside the home screen', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(homeSelectedViewProvider.notifier).state =
        NoteListView.daily;

    expect(container.read(homeSelectedViewProvider), NoteListView.daily);
  });

  test('sorts within pinned notes by the selected order', () {
    final notes = [
      note('Zulu', 1, pinned: true),
      note('Newest', 4),
      note('Alpha', 2, pinned: true),
      note('Middle', 3),
    ];

    expect(
      sortAndFilterNotes(
        notes,
        sort: NoteListSort.alphabetical,
        deselectedFolders: const {},
      ).map((note) => note.title),
      ['Alpha', 'Zulu', 'Middle', 'Newest'],
    );
    expect(
      sortAndFilterNotes(
        notes,
        sort: NoteListSort.lastUpdated,
        deselectedFolders: const {},
      ).map((note) => note.title),
      ['Alpha', 'Zulu', 'Newest', 'Middle'],
    );
  });

  test('confirms a refresh when GitHub has no new changes', () {
    expect(
      syncRefreshMessage(
        const SyncResult.success('Synced with GitHub', noRemoteChanges: true),
      ),
      'Checked GitHub — no new changes found.',
    );
  });

  test('labels and filters top-level note folders only', () {
    final daily = note('Today', 1, path: 'daily/2026-08-08.md');
    final project = note('Plan', 2, path: 'projects/alpha/plan.md');
    final root = note('Inbox', 3);
    final asset = note('Image', 4, path: 'assets/logo.md');

    expect(noteFolderLabel(daily), 'daily');
    expect(noteFolderLabel(project), 'projects');
    expect(noteFolderLabel(asset), isNull);
    expect(noteFolders([project, daily, root, asset]), ['daily', 'projects']);
    expect(creationFolders([project, daily, root, asset]), ['projects']);
    expect(
      sortAndFilterNotes(
        [daily, project, root],
        sort: NoteListSort.alphabetical,
        deselectedFolders: const {'daily'},
      ).map((note) => note.title),
      ['Inbox', 'Plan'],
    );
  });

  test(
    'separates note types using Reflect metadata or established folders',
    () {
      final regular = note('Plan', 1, path: 'notes/plan.md');
      final typedMeeting = note(
        'Review',
        2,
        path: 'notes/review.md',
        body: '- Type: #meeting',
      );
      final folderPerson = note('Avery', 3, path: 'people/avery.md');

      expect(noteObjectType(regular), NoteObjectType.note);
      expect(noteObjectType(typedMeeting), NoteObjectType.meeting);
      expect(noteObjectType(folderPerson), NoteObjectType.person);
      expect(
        sortAndFilterNotes(
          [regular, typedMeeting, folderPerson],
          sort: NoteListSort.lastUpdated,
          view: NoteListView.meetings,
        ).map((note) => note.title),
        ['Review'],
      );
    },
  );

  test('prefers a person email field and finds legacy email addresses', () {
    final person = note(
      'Avery',
      1,
      body: '''
- Type: #person
- Email: avery@example.com

Backup: other@example.com
''',
    );
    final legacyPerson = note('Robin', 2, body: 'Contact robin@example.org');

    expect(noteEmailAddress(person), 'avery@example.com');
    expect(noteEmailAddress(legacyPerson), 'robin@example.org');
  });

  test(
    'groups meetings by their title date before their last updated date',
    () {
      final older = note('Older', 0, path: 'meetings/older.md');
      final firstToday = note(
        'First today — July 15, 2026',
        DateTime(2026, 8, 13, 8).millisecondsSinceEpoch,
        path: 'meetings/first-today.md',
      );
      final secondToday = note(
        'Second today July15,2026',
        DateTime(2026, 8, 13, 16).millisecondsSinceEpoch,
        path: 'meetings/second-today.md',
      );

      final groups = groupMeetingsByDate([older, firstToday, secondToday]);

      expect(groups, hasLength(2));
      expect(groups.first.date, DateTime(2026, 7, 15));
      expect(groups.first.notes.map((note) => note.title), [
        'First today — July 15, 2026',
        'Second today July15,2026',
      ]);
    },
  );

  test(
    'uses an ordinal date in the visible title over filename-like numbers',
    () {
      final noteWithConflictingPath = note(
        'Joel / Mark 1:1 - July 16th, 2026',
        DateTime(2026, 8, 11, 9).millisecondsSinceEpoch,
        path: 'meeting/joel-mark-11-july-16th-2026.md',
      );

      final groups = groupMeetingsByDate([noteWithConflictingPath]);

      expect(groups.single.date, DateTime(2026, 7, 16));
    },
  );

  test('recognizes supported title-date conventions without guessing', () {
    expect(
      meetingDateFromTitle('Planning — 2026-08-13'),
      DateTime(2026, 8, 13),
    );
    expect(meetingDateFromTitle('Planning 8/13/2026'), DateTime(2026, 8, 13));
    expect(
      meetingDateFromTitle('Planning 13 August 2026'),
      DateTime(2026, 8, 13),
    );
    expect(meetingDateFromTitle('JoelTaylorJune4-2026'), DateTime(2026, 6, 4));
    expect(
      meetingDateFromTitle('Joel / Mark 1:1 - July 16th, 2026'),
      DateTime(2026, 7, 16),
    );
    expect(meetingDateFromTitle('Planning August 32, 2026'), isNull);
    expect(meetingDateFromTitle('Planning August 2026'), isNull);
  });

  test('keeps existing to-dos in place when their note is updated', () {
    TodoItem todo(String noteId, int taskIndex, String text, bool completed) =>
        TodoItem(
          noteId: noteId,
          taskIndex: taskIndex,
          text: text,
          isCompleted: completed,
          noteTitle: noteId,
        );

    final beforeUpdate = [
      todo('newer-note', 0, 'Third task', false),
      todo('older-note', 0, 'First task', false),
      todo('older-note', 1, 'Second task', false),
    ];
    final afterUpdate = [
      todo('older-note', 0, 'First task', true),
      todo('older-note', 1, 'Second task', false),
      todo('newer-note', 0, 'Third task', false),
    ];

    final stableOrder = preserveTodoOrder(afterUpdate, beforeUpdate);

    expect(stableOrder.map((todo) => todo.text), [
      'Third task',
      'First task',
      'Second task',
    ]);
    expect(stableOrder[1].isCompleted, isTrue);
  });

  test('keeps to-dos together when a note gains a task', () {
    TodoItem todo(String noteId, int taskIndex, String text) => TodoItem(
      noteId: noteId,
      taskIndex: taskIndex,
      text: text,
      isCompleted: false,
      noteTitle: noteId,
    );

    final stableOrder = preserveTodoOrder(
      [
        todo('updated-note', 0, 'First task'),
        todo('updated-note', 1, 'New task'),
        todo('other-note', 0, 'Other task'),
      ],
      [
        todo('other-note', 0, 'Other task'),
        todo('updated-note', 0, 'First task'),
      ],
    );

    expect(
      groupTodosByNote(
        stableOrder,
      ).map((group) => group.map((todo) => todo.text).toList()).toList(),
      [
        ['Other task'],
        ['First task', 'New task'],
      ],
    );
  });
}
