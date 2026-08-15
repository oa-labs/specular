import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:specular/src/data/note_repository.dart';
import 'package:specular/src/domain/note.dart';
import 'package:specular/src/ui/note_body_editor.dart';

Note _note({required String title, required String body}) => Note(
  id: 'note-id',
  title: title,
  path: 'notes/example.md',
  rawMarkdown: body,
  body: body,
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
  updatedAt: DateTime(2026),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'inserts a staged image when the editor selection is unavailable',
    () async {
      final editorState = EditorState(
        document: Document.blank(withInitialText: true),
      );
      addTearDown(editorState.dispose);

      await NoteBodyEditorCodec.insertStagedImage(
        editorState,
        const StagedImage(
          localPath: '/temporary/image.jpg',
          attachmentPath: 'attachments/image.jpg',
          mimeType: 'image/jpeg',
        ),
        'attachments/image.jpg',
      );

      expect(
        NoteBodyEditorCodec.export(editorState),
        '![](attachments/image.jpg)',
      );
      expect(editorState.selection?.start.path, [1]);
      expect(editorState.getNodeAtPath([1])?.type, ParagraphBlockKeys.type);
    },
  );

  test(
    'inserts text at a retained cursor after a modal clears selection',
    () async {
      final editorState = EditorState(
        document: Document(
          root: Node(
            type: 'page',
            children: [paragraphNode(text: 'Before')],
          ),
        ),
      );
      addTearDown(editorState.dispose);
      final retainedSelection = Selection.collapsed(
        Position(path: [0], offset: 2),
      );
      editorState.selection = null;

      await NoteBodyEditorCodec.insertTextAtSelectionOrEnd(
        editorState,
        '[[Project]]',
        retainedSelection: retainedSelection,
      );

      expect(
        editorState.getNodeAtPath([0])?.delta?.toPlainText(),
        'Be[[Project]]fore',
      );
      expect(editorState.selection?.start, Position(path: [0], offset: 13));
    },
  );

  test('appends text when the editor selection is unavailable', () async {
    final editorState = EditorState(
      document: Document.blank(withInitialText: true),
    );
    addTearDown(editorState.dispose);

    await NoteBodyEditorCodec.insertTextAtSelectionOrEnd(
      editorState,
      '[[Project]]',
    );

    expect(NoteBodyEditorCodec.export(editorState), '[[Project]]');
    expect(editorState.selection?.start, Position(path: [0], offset: 11));
  });

  test('adds an editable line when a note contains only an image', () async {
    final editorState = EditorState(
      document: Document(
        root: Node(
          type: 'page',
          children: [imageNode(url: '/temporary/image.jpg')],
        ),
      ),
    );
    addTearDown(editorState.dispose);

    await NoteBodyEditorCodec.insertTextAtSelectionOrEnd(
      editorState,
      '[[Project]]',
    );

    expect(editorState.getNodeAtPath([1])?.delta?.toPlainText(), '[[Project]]');
  });

  test('excludes the matching persisted title from the editable body', () {
    final note = _note(title: 'Project', body: '# Project\n\nBody text\n');

    expect(NoteBodyEditorCodec.editableBody(note), 'Body text\n');
  });

  test('keeps a nonmatching heading rather than silently dropping it', () {
    final note = _note(
      title: 'Project',
      body: '# Different title\n\nBody text\n',
    );

    expect(NoteBodyEditorCodec.editableBody(note), note.body);
  });

  test('exports AppFlowy to-do blocks as portable Markdown', () {
    final editorState = EditorState(
      document: markdownToDocument('- [ ] Ship the editor'),
    );
    addTearDown(editorState.dispose);

    expect(
      NoteBodyEditorCodec.export(editorState),
      contains('- [ ] Ship the editor'),
    );
  });

  test('preserves formatted to-do text through an editor round trip', () {
    final editorState = EditorState(
      document: markdownToDocument(
        '- [x] **Joel Reed:** Review the email file and confirm the XML.',
      ),
    );
    addTearDown(editorState.dispose);

    expect(
      NoteBodyEditorCodec.export(editorState),
      contains('**Joel Reed:** Review the email file and confirm the XML.'),
    );
  });

  test('keeps exported task list items contiguous', () {
    final editorState = EditorState(
      document: markdownToDocument('- [x] Done\n- [ ] Open'),
    );
    addTearDown(editorState.dispose);

    expect(NoteBodyEditorCodec.export(editorState), '- [x] Done\n- [ ] Open');
  });

  test('exports tagged global tasks with Reflect plus markers', () {
    final editorState = EditorState(
      document: Document(
        root: Node(
          type: 'page',
          children: [
            todoListNode(
              checked: false,
              text: 'Global task',
              attributes: const {NoteBodyEditorCodec.globalTaskAttribute: true},
            ),
            todoListNode(checked: false, text: 'Local checkbox'),
          ],
        ),
      ),
    );
    addTearDown(editorState.dispose);

    expect(
      NoteBodyEditorCodec.export(editorState),
      '+ [ ] Global task\n- [ ] Local checkbox',
    );
  });

  test('restores global task markers when loading Markdown', () {
    final editorState = EditorState(
      document: NoteBodyEditorCodec.documentFromMarkdown(
        '+ [x] Global task\n\n- [ ] Local checkbox',
      ),
    );
    addTearDown(editorState.dispose);

    expect(
      NoteBodyEditorCodec.export(editorState),
      '+ [x] Global task\n- [ ] Local checkbox',
    );
  });

  test('warns for Markdown outside the supported rich-text subset', () {
    expect(
      MarkdownCompatibility.requiresRewriteWarning('[[Project plan]]'),
      isTrue,
    );
    expect(
      MarkdownCompatibility.requiresRewriteWarning('```dart\nprint(1);\n```'),
      isTrue,
    );
    expect(
      MarkdownCompatibility.requiresRewriteWarning('## Heading\n\n- [ ] Task'),
      isFalse,
    );
  });
}
