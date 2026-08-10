import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
