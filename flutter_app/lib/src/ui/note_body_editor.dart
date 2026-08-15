import 'package:appflowy_editor/appflowy_editor.dart';

import '../data/note_repository.dart';
import '../domain/markdown.dart';
import '../domain/note.dart';

/// Keeps the editor's document model at the UI boundary. Markdown remains the
/// canonical data stored by [NoteRepository].
class NoteBodyEditorCodec {
  static const _markdownImageUrl = 'specular_markdown_image_url';
  static const globalTaskAttribute = 'specular_global_task';

  static String editableBody(Note note) {
    final match = RegExp(
      r'^#\s+([^\r\n]+)\r?\n(?:\r?\n)?',
    ).firstMatch(note.body);
    if (match == null || match.group(1)?.trim() != note.title.trim()) {
      return note.body;
    }
    return note.body.substring(match.end);
  }

  static Future<EditorState> load(Note? note, NoteRepository repository) async {
    if (note == null) return EditorState.blank(withInitialText: true);
    var document = documentFromMarkdown(editableBody(note));
    if (document.isEmpty) document = Document.blank(withInitialText: true);
    document = await _resolveAttachmentPaths(document, note, repository);
    return EditorState(document: document);
  }

  static String export(EditorState editorState) => normalizeTaskListSpacing(
    MarkdownContract.restoreWikiLinks(
      documentToMarkdown(
        editorState.document,
        customParsers: const [
          _SpecularImageNodeParser(),
          _SpecularTodoNodeParser(),
        ],
        lineBreak: '\n\n',
      ),
    ),
  ).trim();

  /// Keeps adjacent GFM task items in a tight list. AppFlowy exports a blank
  /// line after every block, but its Markdown importer and flutter_markdown
  /// only recognize task markers when the list items are contiguous.
  static String normalizeTaskListSpacing(
    String markdown,
  ) => markdown.replaceAllMapped(
    RegExp(
      r'(^[ \t]*[-*+]\s+\[[ xX]\][^\r\n]*)\r?\n(?:[ \t]*\r?\n)+(?=[ \t]*[-*+]\s+\[[ xX]\])',
      multiLine: true,
    ),
    (match) => '${match.group(1)}\n',
  );

  static Document documentFromMarkdown(String markdown) {
    final normalized = normalizeTaskListSpacing(
      MarkdownContract.renderWikiLinks(markdown),
    );
    return _restoreGlobalTaskKinds(markdownToDocument(normalized), normalized);
  }

  /// AppFlowy's Markdown AST does not retain whether a task used `+` or `-`.
  /// Pair the parsed task nodes with source-order task markers so a global
  /// Reflect task can survive a rich-text round trip.
  static Document _restoreGlobalTaskKinds(Document document, String markdown) {
    final globalKinds = <bool>[
      for (final match in RegExp(
        r'^[ \t]*([-*+])\s+\[[ xX]\]',
        multiLine: true,
      ).allMatches(markdown))
        match.group(1) == '+',
    ];
    var taskIndex = 0;

    Node mapNode(Node node) {
      final children = [for (final child in node.children) mapNode(child)];
      if (node.type != TodoListBlockKeys.type) {
        return node.copyWith(children: children);
      }
      final isGlobal =
          taskIndex < globalKinds.length && globalKinds[taskIndex++];
      return node.copyWith(
        children: children,
        attributes: {
          ...node.attributes,
          if (isGlobal) globalTaskAttribute: true,
        },
      );
    }

    return Document(root: mapNode(document.root));
  }

  static Future<void> insertStagedImage(
    EditorState editorState,
    StagedImage image,
    String markdownReference,
  ) async {
    // The image picker can clear the editor's selection while it is open.
    // AppFlowy's insertImageNode then silently returns without inserting
    // anything, so choose the current block when available or append to the
    // document as a dependable fallback.
    final selectedNode = editorState.selection == null
        ? null
        : editorState.getNodeAtPath(editorState.selection!.end.path);
    final insertionNode =
        selectedNode ??
        (editorState.document.root.children.isEmpty
            ? null
            : editorState.document.root.children.last);
    if (insertionNode == null) {
      throw StateError('The note has no block where an image can be inserted.');
    }

    final replacesEmptyParagraph =
        insertionNode.type == ParagraphBlockKeys.type &&
        (insertionNode.delta?.isEmpty ?? false);
    final insertedPath = replacesEmptyParagraph
        ? insertionNode.path
        : insertionNode.path.next;
    final editablePath = insertedPath.next;
    final transaction = editorState.transaction;
    if (replacesEmptyParagraph) {
      transaction
        ..insertNode(insertedPath, imageNode(url: image.localPath))
        ..deleteNode(insertionNode)
        ..insertNode(editablePath, paragraphNode());
    } else {
      transaction
        ..insertNode(insertedPath, imageNode(url: image.localPath))
        ..insertNode(editablePath, paragraphNode());
    }
    transaction.afterSelection = Selection.collapsed(
      Position(path: editablePath, offset: 0),
    );
    await editorState.apply(transaction);

    final inserted = editorState.getNodeAtPath(insertedPath);
    if (inserted == null || inserted.type != ImageBlockKeys.type) {
      throw StateError('The image could not be inserted into the note.');
    }
    final editable = editorState.getNodeAtPath(editablePath);
    if (editable == null || editable.type != ParagraphBlockKeys.type) {
      throw StateError('The image has no editable line after it.');
    }
    final updateTransaction = editorState.transaction
      ..updateNode(inserted, {_markdownImageUrl: markdownReference})
      ..afterSelection = Selection.collapsed(
        Position(path: editablePath, offset: 0),
      );
    await editorState.apply(updateTransaction);
  }

  /// Inserts text at the editor cursor retained before a modal flow, or at the
  /// end of the last editable block when that flow cleared the selection.
  ///
  /// AppFlowy's [EditorState.insertTextAtCurrentSelection] intentionally does
  /// nothing without a collapsed selection. That is common after a native
  /// picker or a modal bottom sheet has focused one of its own text fields.
  static Future<void> insertTextAtSelectionOrEnd(
    EditorState editorState,
    String text, {
    Selection? retainedSelection,
    Attributes? attributes,
  }) async {
    final selection =
        _validCollapsedSelection(editorState, retainedSelection) ??
        _validCollapsedSelection(editorState, editorState.selection);
    var node = selection == null
        ? _lastEditableRootNode(editorState)
        : editorState.getNodeAtPath(selection.start.path);
    if (node == null || node.delta == null) {
      // A note imported with only an image has no text block. Add one rather
      // than making the link action fail after the picker closes.
      final path = editorState.document.root.children.isEmpty
          ? <int>[0]
          : editorState.document.root.children.last.path.next;
      await editorState.apply(
        editorState.transaction
          ..insertNode(path, paragraphNode())
          ..afterSelection = Selection.collapsed(
            Position(path: path, offset: 0),
          ),
      );
      node = editorState.getNodeAtPath(path);
      if (node == null || node.delta == null) {
        throw StateError(
          'The note has no editable line where text can be inserted.',
        );
      }
    }

    final offset = selection == null
        ? node.delta!.length
        : selection.start.offset.clamp(0, node.delta!.length).toInt();
    final transaction = editorState.transaction
      ..insertText(node, offset, text, attributes: attributes)
      ..afterSelection = Selection.collapsed(
        Position(path: node.path, offset: offset + text.length),
      );
    await editorState.apply(transaction);
  }

  static Selection? _validCollapsedSelection(
    EditorState editorState,
    Selection? selection,
  ) {
    if (selection == null || !selection.isCollapsed) return null;
    return editorState.getNodeAtPath(selection.start.path)?.delta == null
        ? null
        : selection;
  }

  static Node? _lastEditableRootNode(EditorState editorState) {
    for (final node in editorState.document.root.children.reversed) {
      if (node.delta != null) return node;
    }
    return null;
  }

  static Future<Document> _resolveAttachmentPaths(
    Document document,
    Note note,
    NoteRepository repository,
  ) async {
    Future<Node> mapNode(Node node) async {
      final children = <Node>[
        for (final child in node.children) await mapNode(child),
      ];
      if (node.type != ImageBlockKeys.type) {
        return node.copyWith(children: children);
      }
      final source = node.attributes[ImageBlockKeys.url] as String?;
      if (source == null) return node.copyWith(children: children);
      final file = await repository.resolveAttachment(note.path, source);
      return node.copyWith(
        children: children,
        attributes: {
          ...node.attributes,
          _markdownImageUrl: source,
          if (file != null) ImageBlockKeys.url: file.path,
        },
      );
    }

    return Document(root: await mapNode(document.root));
  }
}

/// A deliberately conservative preflight: a warning is better than silently
/// claiming a source feature can survive a rich-text round trip.
class MarkdownCompatibility {
  static final _unsupported = <RegExp>[
    RegExp(r'^\s*```', multiLine: true),
    RegExp(r'^\s*\[[^\]]+\]:\s*\S+', multiLine: true),
    RegExp(r'^\s*\|.*\|\s*$', multiLine: true),
    RegExp(r'<[/!]?[A-Za-z][^>]*>'),
    RegExp(r'!\[[^\]]+\]\([^)]*\)'),
  ];

  static bool requiresRewriteWarning(String markdown) =>
      _unsupported.any((pattern) => pattern.hasMatch(markdown));
}

class _SpecularImageNodeParser extends NodeParser {
  const _SpecularImageNodeParser();

  @override
  String get id => ImageBlockKeys.type;

  @override
  String transform(Node node, DocumentMarkdownEncoder? encoder) {
    final attributes = node.attributes;
    final source =
        attributes[NoteBodyEditorCodec._markdownImageUrl] ??
        attributes[ImageBlockKeys.url];
    return '![]($source)';
  }
}

class _SpecularTodoNodeParser extends NodeParser {
  const _SpecularTodoNodeParser();

  @override
  String get id => TodoListBlockKeys.type;

  @override
  String transform(Node node, DocumentMarkdownEncoder? encoder) {
    final delta = node.delta ?? (Delta()..insert(''));
    final marker =
        node.attributes[NoteBodyEditorCodec.globalTaskAttribute] == true
        ? '+'
        : '-';
    final checked = node.attributes[TodoListBlockKeys.checked] == true
        ? '[x]'
        : '[ ]';
    final children = encoder?.convertNodes(node.children, withIndent: true);
    var markdown =
        '$marker $checked ${DeltaMarkdownEncoder().convert(delta)}\n';
    if (children != null && children.isNotEmpty) markdown += children;
    return markdown;
  }
}
