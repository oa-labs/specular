class ParsedMarkdown {
  const ParsedMarkdown({
    required this.id,
    required this.aliases,
    required this.title,
    required this.body,
    required this.frontmatter,
  });

  final String? id;
  final List<String> aliases;
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
      title: titleMatch?.group(1)?.trim() ?? '',
      body: body,
      frontmatter: frontmatter,
    );
  }

  static String identityFor(String path, String? id) =>
      id?.isNotEmpty == true ? id! : (path.startsWith('daily/') ? path : path);

  static String frontmatter(String id, [List<String> aliases = const []]) {
    final aliasLines = aliases.isEmpty
        ? ''
        : 'aliases:\n${aliases.map((value) => '  - $value').join('\n')}\n';
    return '---\nid: $id\n$aliasLines---\n';
  }

  static String snippet(String body) => body
      .replaceAll(RegExp(r'^#.+$', multiLine: true), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
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
