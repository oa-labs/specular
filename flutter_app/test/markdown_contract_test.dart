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

    test('renders and restores portable wiki links', () {
      const source = 'See [[Project plan]] and [[  Meeting notes  ]].';

      final rendered = MarkdownContract.renderWikiLinks(source);

      expect(
        rendered,
        'See [Project plan](specular-wiki:?title=Project+plan) and '
        '[Meeting notes](specular-wiki:?title=Meeting+notes).',
      );
      expect(
        MarkdownContract.wikiLinkTitle('specular-wiki:?title=Project+plan'),
        'Project plan',
      );
      expect(
        MarkdownContract.restoreWikiLinks(rendered),
        'See [[Project plan]] and [[Meeting notes]].',
      );
    });

    test('resolves Markdown links relative to their source note', () {
      expect(
        MarkdownContract.resolveNoteLink(
          'daily/2026-08-09.md',
          '../notes/AngelInvesting.md',
        ),
        'notes/AngelInvesting.md',
      );
      expect(
        MarkdownContract.resolveNoteLink(
          'projects/portfolio/overview.md',
          '../../notes/InvestmentStrategy.md#allocation',
        ),
        'notes/InvestmentStrategy.md',
      );
      expect(
        MarkdownContract.resolveNoteLink(
          'daily/2026-08-09.md',
          '../notes/AiAgentsDeepDiveApril7,2026.md',
        ),
        'notes/AiAgentsDeepDiveApril7,2026.md',
      );
      expect(
        MarkdownContract.resolveNoteLink(
          'daily/2026-08-09.md',
          '../meetings/ExecutiveAssistantGuidelines.md',
        ),
        'meetings/ExecutiveAssistantGuidelines.md',
      );
      expect(
        MarkdownContract.resolveNoteLink(
          'daily/2026-08-09.md',
          '../meetings/NewWebsiteDesignReviewJuly15,2026.md',
        ),
        'meetings/NewWebsiteDesignReviewJuly15,2026.md',
      );
      expect(
        MarkdownContract.resolveNoteLink(
          'daily/2026-08-09.md',
          '../meetings/JoelTaylorJune4-2026.md',
        ),
        'meetings/JoelTaylorJune4-2026.md',
      );
    });

    test('does not resolve external or repository-escaping links as notes', () {
      expect(
        MarkdownContract.resolveNoteLink(
          'daily/2026-08-09.md',
          'https://example.com/note.md',
        ),
        isNull,
      );
      expect(
        MarkdownContract.resolveNoteLink('note.md', '../outside.md'),
        isNull,
      );
    });

    test('rebases inbound and outbound links when a note moves', () {
      expect(
        MarkdownContract.rebaseNoteLinks(
          '[Plan](../projects/alpha/project-plan.md#next)',
          oldSourcePath: 'daily/2026-08-09.md',
          newSourcePath: 'daily/2026-08-09.md',
          movedFromPath: 'projects/alpha/project-plan.md',
          movedToPath: 'archive/project-plan.md',
        ),
        '[Plan](../archive/project-plan.md#next)',
      );
      expect(
        MarkdownContract.rebaseNoteLinks(
          '''[Research](../../notes/research.md)
[Self](project-plan.md)
[External](https://example.com/project-plan.md)''',
          oldSourcePath: 'projects/alpha/project-plan.md',
          newSourcePath: 'archive/project-plan.md',
          movedFromPath: 'projects/alpha/project-plan.md',
          movedToPath: 'archive/project-plan.md',
        ),
        '''[Research](../notes/research.md)
[Self](project-plan.md)
[External](https://example.com/project-plan.md)''',
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

    test('skips empty global tasks without changing later task indexes', () {
      const source = '+ [ ]\n+ [ ] Actual task\n+ [x]   ';

      final tasks = TodoMarkdown.extract(source);

      expect(tasks.map((task) => task.text), ['Actual task']);
      expect(tasks.single.index, 1);
      expect(
        TodoMarkdown.toggleGlobalAt(source, tasks.single.index),
        '+ [ ]\n+ [x] Actual task\n+ [x]   ',
      );
    });
  });
}
