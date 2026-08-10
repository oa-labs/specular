import 'package:flutter_test/flutter_test.dart';
import 'package:specular/src/domain/note.dart';
import 'package:specular/src/ui/screens.dart';

void main() {
  Note note(String title, int updatedAt, {String? path, bool pinned = false}) =>
      Note(
        id: title,
        title: title,
        path: path ?? '$title.md',
        rawMarkdown: '',
        body: '',
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
}
