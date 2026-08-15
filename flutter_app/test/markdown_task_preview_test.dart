import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:specular/src/domain/markdown.dart';
import 'package:specular/src/ui/note_body_editor.dart';

void main() {
  testWidgets('renders normalized task-list items as interactive checkboxes', (
    tester,
  ) async {
    const source = '- [x] **Done task**\n\n- [ ] **Open task**';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Markdown(
            data: NoteBodyEditorCodec.normalizeTaskListSpacing(source),
            checkboxBuilder: (checked) =>
                Checkbox(value: checked, onChanged: (_) {}),
          ),
        ),
      ),
    );

    expect(find.byType(Checkbox), findsNWidgets(2));
  });

  testWidgets('renders wiki links as tappable Markdown links', (tester) async {
    String? tappedHref;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Markdown(
            data: MarkdownContract.renderWikiLinks('[[Project plan]]'),
            onTapLink: (_, href, _) => tappedHref = href,
          ),
        ),
      ),
    );

    await tester.tap(find.text('Project plan', findRichText: true));

    expect(MarkdownContract.wikiLinkTitle(tappedHref ?? ''), 'Project plan');
  });
}
