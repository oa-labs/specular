import 'package:appflowy_editor/appflowy_editor.dart';

import '../data/note_repository.dart';
import '../domain/note.dart';

/// Keeps the editor's document model at the UI boundary. Markdown remains the
/// canonical data stored by [NoteRepository].
class NoteBodyEditorCodec {
  static const _markdownImageUrl = 'specular_markdown_image_url';

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
    var document = markdownToDocument(editableBody(note));
    if (document.isEmpty) document = Document.blank(withInitialText: true);
    document = await _resolveAttachmentPaths(document, note, repository);
    return EditorState(document: document);
  }

  static String export(EditorState editorState) => documentToMarkdown(
    editorState.document,
    customParsers: const [_SpecularImageNodeParser()],
    lineBreak: '\n\n',
  ).trim();

  static Future<void> insertStagedImage(
    EditorState editorState,
    StagedImage image,
    String markdownReference,
  ) async {
    await editorState.insertImageNode(image.localPath);
    final inserted = editorState.document.root.children.lastWhere(
      (node) => node.type == ImageBlockKeys.type,
    );
    final transaction = editorState.transaction
      ..updateNode(inserted, {_markdownImageUrl: markdownReference});
    await editorState.apply(transaction);
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
    RegExp(r'\[\[[^\]]+\]\]'), // Reflect wiki links.
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
