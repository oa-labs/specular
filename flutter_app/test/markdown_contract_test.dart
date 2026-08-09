import 'package:flutter_test/flutter_test.dart';
import 'package:specular/src/domain/markdown.dart';

void main() {
  group('MarkdownContract', () {
    test('preserves Reflect id, aliases, title, and body', () {
      const raw = '''---
id: 01kxp66n18p7vt6b5rsmd1taqy
aliases:
  - OLLI - University of Pitt
snippet: "An existing portable summary"
---
# A note

Body text
''';

      final note = MarkdownContract.parse(raw);

      expect(note.id, '01kxp66n18p7vt6b5rsmd1taqy');
      expect(note.aliases, ['OLLI - University of Pitt']);
      expect(note.snippet, 'An existing portable summary');
      expect(note.title, 'A note');
      expect(note.body, contains('Body text'));
    });

    test('writes generated snippets back into frontmatter', () {
      const raw = '# A note\n\nBody text\n';

      final updated = MarkdownContract.upsertSnippet(
        raw,
        '01kxp66n18p7vt6b5rsmd1taqy',
        'A "quoted" summary',
      );
      final parsed = MarkdownContract.parse(updated);

      expect(parsed.id, '01kxp66n18p7vt6b5rsmd1taqy');
      expect(parsed.snippet, 'A "quoted" summary');
      expect(parsed.body, raw);
    });

    test('daily paths remain stable identities without frontmatter', () {
      final parsed = MarkdownContract.parse('# 2026-08-08\n');
      expect(
        MarkdownContract.identityFor('daily/2026-08-08.md', parsed.id),
        'daily/2026-08-08.md',
      );
    });
  });

  group('TodoMarkdown', () {
    test('extracts and toggles task index without touching other markdown', () {
      const source = '- [ ] First\n- [x] Second\nParagraph';
      final tasks = TodoMarkdown.extract(source);

      expect(tasks.map((task) => task.completed), [false, true]);
      expect(
        TodoMarkdown.toggleAt(source, 0),
        '- [x] First\n- [x] Second\nParagraph',
      );
    });
  });
}
