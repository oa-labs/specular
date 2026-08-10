import 'package:flutter_test/flutter_test.dart';
import 'package:specular/src/domain/markdown.dart';

void main() {
  group('MarkdownContract', () {
    test('preserves Reflect id, aliases, title, and body', () {
      const raw = '''---
id: 01kxp66n18p7vt6b5rsmd1taqy
aliases:
  - OLLI - University of Pitt
summary: "An existing portable summary"
---
# A note

Body text
''';

      final note = MarkdownContract.parse(raw);

      expect(note.id, '01kxp66n18p7vt6b5rsmd1taqy');
      expect(note.aliases, ['OLLI - University of Pitt']);
      expect(note.summary, 'An existing portable summary');
      expect(note.title, 'A note');
      expect(note.body, contains('Body text'));
    });

    test('writes generated summaries back into frontmatter', () {
      const raw = '# A note\n\nBody text\n';

      final updated = MarkdownContract.upsertSummary(
        raw,
        '01kxp66n18p7vt6b5rsmd1taqy',
        'A "quoted" summary',
      );
      final parsed = MarkdownContract.parse(updated);

      expect(parsed.id, '01kxp66n18p7vt6b5rsmd1taqy');
      expect(parsed.summary, 'A "quoted" summary');
      expect(parsed.body, raw);
      expect(updated, contains('summary:'));
    });

    test('normalizes summaries to plain text', () {
      const markdown = '''## **Project** update

- [ ] Review [the plan](https://example.com/plan)
> `Before` ~~Friday~~
''';

      expect(
        MarkdownContract.plainText(markdown),
        'Project update Review the plan Before Friday',
      );

      final parsed = MarkdownContract.parse('''---
id: 01summary
summary: "**Project** [plan](https://example.com)"
---
# A note
''');
      expect(parsed.summary, 'Project plan');
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
    test('indexes only global plus tasks and toggles each scope independently', () {
      const source =
          '+ [ ] First global\n- [ ] Local checkbox\n+ [x] Done global\nParagraph';
      final tasks = TodoMarkdown.extract(source);

      expect(tasks.map((task) => task.completed), [false, true]);
      expect(
        TodoMarkdown.toggleGlobalAt(source, 0),
        '+ [x] First global\n- [ ] Local checkbox\n+ [x] Done global\nParagraph',
      );
      expect(
        TodoMarkdown.toggleCheckboxAt(source, 1),
        '+ [ ] First global\n- [x] Local checkbox\n+ [x] Done global\nParagraph',
      );
    });
  });
}
