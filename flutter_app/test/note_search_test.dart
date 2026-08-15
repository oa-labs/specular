import 'package:flutter_test/flutter_test.dart';
import 'package:specular/src/domain/note.dart';
import 'package:specular/src/domain/note_search.dart';

void main() {
  Note note(String title, String body, {int updatedAt = 0}) => Note(
    id: title,
    title: title,
    path: '$title.md',
    rawMarkdown: '',
    body: '# $title\n\n$body',
    summary: null,
    aliases: const [],
    isDaily: false,
    isPinned: false,
    lastRemoteSha: null,
    isDirty: false,
    isPendingDeletion: false,
    pendingRenameFromPath: null,
    pendingRenameFromSha: null,
    isConflict: false,
    updatedAt: DateTime.fromMillisecondsSinceEpoch(updatedAt),
  );

  test('ranks title hits above body hits', () {
    final titleMatch = note('Design review', 'Agenda and decisions');
    final bodyMatch = note('Weekly notes', 'Prepare for the design review');

    final results = rankNotes([
      bodyMatch,
      titleMatch,
    ], NoteSearchQuery('design review'));

    expect(results.map((result) => result.note.title), [
      'Design review',
      'Weekly notes',
    ]);
  });

  test('matches quoted phrases in order and returns an excerpt', () {
    final exact = note(
      'Research',
      'We agreed to run a design review before the release.',
    );
    final separated = note('Planning', 'Design the feature, then review it.');

    final results = rankNotes([
      separated,
      exact,
    ], NoteSearchQuery('"design review"'));

    expect(results.single.note.title, 'Research');
    expect(results.single.excerpt, contains('design review'));
  });

  test('honors title and body scopes', () {
    final titleMatch = note('Design review', 'Agenda');
    final bodyMatch = note('Weekly notes', 'A design review is scheduled.');

    expect(
      rankNotes(
        [titleMatch, bodyMatch],
        NoteSearchQuery('design', scope: NoteSearchScope.title),
      ).map((result) => result.note.title),
      ['Design review'],
    );
    expect(
      rankNotes(
        [titleMatch, bodyMatch],
        NoteSearchQuery('design', scope: NoteSearchScope.body),
      ).map((result) => result.note.title),
      ['Weekly notes'],
    );
  });

  test('returns case-insensitive ranges for result highlighting', () {
    final ranges = searchHighlightRanges(
      'Design review notes',
      NoteSearchQuery('design "review"'),
    );

    expect(ranges, [(0, 6), (7, 13)]);
  });
}
