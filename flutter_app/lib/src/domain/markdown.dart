import 'package:path/path.dart' as p;

class ParsedMarkdown {
  const ParsedMarkdown({
    required this.id,
    required this.aliases,
    required this.summary,
    required this.title,
    required this.body,
    required this.frontmatter,
  });

  final String? id;
  final List<String> aliases;
  final String? summary;
  final String title;
  final String body;
  final String? frontmatter;
}

/// Small, deliberately conservative parser matching the established Reflect
/// contract. Unknown frontmatter is preserved verbatim on note updates.
class MarkdownContract {
  /// Resolves a Markdown note link against the note containing it.
  ///
  /// Returns null for external links, non-Markdown files, and paths that would
  /// escape the repository. Fragments are intentionally ignored here: the
  /// preview opens the destination note but does not yet support heading-level
  /// navigation.
  static String? resolveNoteLink(String sourceNotePath, String href) {
    final uri = Uri.tryParse(href.trim());
    if (uri == null || uri.hasScheme || uri.hasAuthority || uri.path.isEmpty) {
      return null;
    }

    final target = uri.path.replaceAll('\\', '/');
    if (!target.toLowerCase().endsWith('.md')) return null;

    final source = sourceNotePath.replaceAll('\\', '/');
    final parent = p.posix.dirname(p.posix.normalize(source));
    final resolved = p.posix.normalize(
      p.posix.join(parent == '.' ? '' : parent, target),
    );
    if (p.posix.isAbsolute(resolved) ||
        resolved == '..' ||
        resolved.startsWith('../')) {
      return null;
    }
    return resolved;
  }

  static ParsedMarkdown parse(String raw) {
    String? frontmatter;
    var body = raw;
    String? id;
    String? summary;
    final aliases = <String>[];
    if (raw.startsWith('---\n')) {
      final end = raw.indexOf('\n---', 4);
      if (end >= 0) {
        frontmatter = raw.substring(4, end);
        body = raw.substring(end + 4).replaceFirst(RegExp(r'^\n'), '');
        final lines = frontmatter.split('\n');
        for (var index = 0; index < lines.length; index++) {
          final line = lines[index];
          if (line.startsWith('id:')) id = line.substring(3).trim();
          if (line.startsWith('summary:')) {
            final value = _decodeScalar(line.substring('summary:'.length));
            final plainSummary = plainText(value);
            summary = plainSummary.isEmpty ? null : plainSummary;
          }
          if (line.startsWith('aliases:')) {
            for (
              index++;
              index < lines.length && lines[index].trimLeft().startsWith('-');
              index++
            ) {
              aliases.add(lines[index].trimLeft().substring(1).trim());
            }
            index--;
          }
        }
      }
    }
    final titleMatch = RegExp(r'^#\s+(.+)$', multiLine: true).firstMatch(body);
    return ParsedMarkdown(
      id: id,
      aliases: aliases,
      summary: summary,
      title: titleMatch?.group(1)?.trim() ?? '',
      body: body,
      frontmatter: frontmatter,
    );
  }

  static String identityFor(String path, String? id) =>
      id?.isNotEmpty == true ? id! : (path.startsWith('daily/') ? path : path);

  static String frontmatter(
    String id, [
    List<String> aliases = const [],
    String? summary,
  ]) {
    final plainSummary = summary == null ? null : plainText(summary);
    final aliasLines = aliases.isEmpty
        ? ''
        : 'aliases:\n${aliases.map((value) => '  - $value').join('\n')}\n';
    final summaryLine = plainSummary?.isNotEmpty == true
        ? 'summary: ${_encodeScalar(plainSummary!)}\n'
        : '';
    return '---\nid: $id\n$aliasLines$summaryLine---\n';
  }

  /// Persists a generated summary in the portable note metadata.
  static String upsertSummary(String raw, String id, String summary) {
    final parsed = parse(raw);
    final plainSummary = plainText(summary);
    if (parsed.frontmatter == null) {
      return '${frontmatter(id, parsed.aliases, plainSummary)}${parsed.body}';
    }
    final lines = parsed.frontmatter!.split('\n');
    final encoded = 'summary: ${_encodeScalar(plainSummary)}';
    var foundId = false;
    var foundSummary = false;
    for (var index = 0; index < lines.length; index++) {
      if (lines[index].startsWith('id:')) {
        lines[index] = 'id: $id';
        foundId = true;
      } else if (lines[index].startsWith('summary:')) {
        lines[index] = encoded;
        foundSummary = true;
      }
    }
    if (!foundId) lines.insert(0, 'id: $id');
    if (!foundSummary) lines.add(encoded);
    return '---\n${lines.join('\n')}\n---\n${parsed.body}';
  }

  static String _encodeScalar(String value) =>
      '"${value.replaceAll('\\', '\\\\').replaceAll('"', '\\"').replaceAll('\n', ' ').trim()}"';

  static String _decodeScalar(String value) {
    final scalar = value.trim();
    if (scalar.length >= 2 && scalar.startsWith('"') && scalar.endsWith('"')) {
      return scalar
          .substring(1, scalar.length - 1)
          .replaceAll('\\"', '"')
          .replaceAll('\\\\', '\\');
    }
    return scalar.replaceAll(RegExp(r"^'|'$"), '');
  }

  /// Converts Markdown into a concise, one-line plain-text summary.
  ///
  /// Summaries are displayed as UI metadata rather than rendered Markdown, so
  /// this strips presentation syntax from both generated and imported values.
  static String plainText(String markdown) {
    var text = markdown
        .replaceAll(RegExp(r'^\s*```[^\n]*$', multiLine: true), '')
        .replaceAll(RegExp(r'^\s*(?:[-*_]\s*){3,}$', multiLine: true), '')
        .replaceAll(RegExp(r'^\s{0,3}#{1,6}\s+', multiLine: true), '')
        .replaceAll(RegExp(r'^\s*>\s?', multiLine: true), '')
        .replaceAll(
          RegExp(r'^\s*(?:[-+*]|\d+[.)])\s+(?:\[[ xX]\]\s*)?', multiLine: true),
          '',
        )
        .replaceAll(RegExp(r'^\s*\[[^\]]+\]:\s*\S+.*$', multiLine: true), '');
    text = text.replaceAllMapped(
      RegExp(r'!\[([^\]]*)\]\([^)]*\)'),
      (match) => match.group(1) ?? '',
    );
    text = text.replaceAllMapped(
      RegExp(r'\[([^\]]+)\]\([^)]*\)'),
      (match) => match.group(1) ?? '',
    );
    text = text.replaceAllMapped(
      RegExp(r'\[([^\]]+)\]\[[^\]]*\]'),
      (match) => match.group(1) ?? '',
    );
    return text
        .replaceAllMapped(
          RegExp(r'<(https?://[^>\s]+)>'),
          (match) => match.group(1) ?? '',
        )
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll(RegExp(r'[*_~`]+'), '')
        .replaceAll(RegExp(r'\\([\\`*_{}\[\]<>()#+\-.!|])'), r'$1')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}

class TodoMarkdown {
  static final _checkbox = RegExp(
    r'^\s*[-*+]\s+\[([ xX])\]\s*(.*)$',
    multiLine: true,
  );
  static final _globalTask = RegExp(
    r'^\s*\+\s+\[([ xX])\]\s*(.*)$',
    multiLine: true,
  );

  /// Reflect global tasks use a `+` marker. `-` and `*` checkbox rows remain
  /// local to their note and deliberately do not enter the task index.
  static List<({int index, String text, bool completed})> extract(
    String markdown,
  ) => [
    for (final (index, match) in _globalTask.allMatches(markdown).indexed)
      (
        index: index,
        text: match.group(2)?.trim() ?? '',
        completed: match.group(1)?.toLowerCase() == 'x',
      ),
  ];

  /// Toggles a task by its index within the global `+` task list.
  static String toggleGlobalAt(String markdown, int taskIndex) =>
      _toggleAt(markdown, taskIndex, _globalTask);

  /// Toggles a checkbox by its index among every checkbox in a note. This is
  /// used by the note preview, where local and global checkboxes are both
  /// interactive.
  static String toggleCheckboxAt(String markdown, int taskIndex) =>
      _toggleAt(markdown, taskIndex, _checkbox);

  static String _toggleAt(String markdown, int taskIndex, RegExp pattern) {
    var current = 0;
    return markdown.replaceAllMapped(pattern, (match) {
      if (current++ != taskIndex) return match.group(0)!;
      final marker = match.group(1)?.toLowerCase() == 'x' ? ' ' : 'x';
      return match.group(0)!.replaceFirst(RegExp(r'\[.\]'), '[$marker]');
    });
  }
}
