class ParsedMarkdown {
  const ParsedMarkdown({
    required this.id,
    required this.aliases,
    required this.snippet,
    required this.title,
    required this.body,
    required this.frontmatter,
  });

  final String? id;
  final List<String> aliases;
  final String? snippet;
  final String title;
  final String body;
  final String? frontmatter;
}

/// Small, deliberately conservative parser matching the established Reflect
/// contract. Unknown frontmatter is preserved verbatim on note updates.
class MarkdownContract {
  static ParsedMarkdown parse(String raw) {
    String? frontmatter;
    var body = raw;
    String? id;
    String? snippet;
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
          if (line.startsWith('snippet:')) {
            final value = _decodeScalar(line.substring('snippet:'.length));
            final plainSnippet = plainText(value);
            snippet = plainSnippet.isEmpty ? null : plainSnippet;
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
      snippet: snippet,
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
    String? snippet,
  ]) {
    final plainSnippet = snippet == null ? null : plainText(snippet);
    final aliasLines = aliases.isEmpty
        ? ''
        : 'aliases:\n${aliases.map((value) => '  - $value').join('\n')}\n';
    final snippetLine = plainSnippet?.isNotEmpty == true
        ? 'snippet: ${_encodeScalar(plainSnippet!)}\n'
        : '';
    return '---\nid: $id\n$aliasLines$snippetLine---\n';
  }

  /// Persists a generated summary in the portable note metadata.
  static String upsertSnippet(String raw, String id, String snippet) {
    final parsed = parse(raw);
    final plainSnippet = plainText(snippet);
    if (parsed.frontmatter == null) {
      return '${frontmatter(id, parsed.aliases, plainSnippet)}${parsed.body}';
    }
    final lines = parsed.frontmatter!.split('\n');
    final encoded = 'snippet: ${_encodeScalar(plainSnippet)}';
    var foundId = false;
    var foundSnippet = false;
    for (var index = 0; index < lines.length; index++) {
      if (lines[index].startsWith('id:')) {
        lines[index] = 'id: $id';
        foundId = true;
      } else if (lines[index].startsWith('snippet:')) {
        lines[index] = encoded;
        foundSnippet = true;
      }
    }
    if (!foundId) lines.insert(0, 'id: $id');
    if (!foundSnippet) lines.add(encoded);
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
  /// Snippets are displayed as UI metadata rather than rendered Markdown, so
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

  static String snippet(String body) => plainText(body);
}

class TodoMarkdown {
  static final _task = RegExp(
    r'^\s*[-*+]\s+\[([ xX])\]\s*(.*)$',
    multiLine: true,
  );

  static List<({int index, String text, bool completed})> extract(
    String markdown,
  ) => [
    for (final (index, match) in _task.allMatches(markdown).indexed)
      (
        index: index,
        text: match.group(2)?.trim() ?? '',
        completed: match.group(1)?.toLowerCase() == 'x',
      ),
  ];

  static String toggleAt(String markdown, int taskIndex) {
    var current = 0;
    return markdown.replaceAllMapped(_task, (match) {
      if (current++ != taskIndex) return match.group(0)!;
      final marker = match.group(1)?.toLowerCase() == 'x' ? ' ' : 'x';
      return match.group(0)!.replaceFirst(RegExp(r'\[.\]'), '[$marker]');
    });
  }
}
