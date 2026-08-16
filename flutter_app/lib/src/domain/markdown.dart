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

/// A resolved-on-index link reference from canonical note Markdown.
class NoteLinkReference {
  const NoteLinkReference({
    required this.kind,
    required this.target,
    required this.label,
  });

  /// `wiki` targets are titles/aliases; `markdown` targets are repository
  /// paths resolved relative to the source note.
  final String kind;
  final String target;
  final String label;
}

/// Small, deliberately conservative parser matching the established Reflect
/// contract. Unknown frontmatter is preserved verbatim on note updates.
class MarkdownContract {
  static const _wikiLinkScheme = 'specular-wiki';

  static final _inlineLinkDestination = RegExp(
    r'(!?\[[^\]\n]*\]\()(<[^>\n]*>|[^\s)\n]+)',
  );
  static final _wikiLink = RegExp(r'\[\[([^\]\r\n]+)\]\]');
  static final _renderedWikiLink = RegExp(
    r'\[([^\]\r\n]+)\]\((specular-wiki:\?title=[^\s)\r\n]+)\)',
  );

  /// Turns Reflect's portable `[[wikilink]]` form into ordinary Markdown that
  /// the app's renderer and rich-text editor can display as an interactive
  /// link. The original form is restored before saving.
  static String renderWikiLinks(String markdown) =>
      markdown.replaceAllMapped(_wikiLink, (match) {
        final title = match.group(1)!.trim();
        if (title.isEmpty) return match.group(0)!;
        return '[$title](${wikiLinkHref(title)})';
      });

  /// Restores internal wiki links after the rich-text editor serializes them
  /// as ordinary Markdown links.
  static String restoreWikiLinks(String markdown) =>
      markdown.replaceAllMapped(_renderedWikiLink, (match) {
        final title = wikiLinkTitle(match.group(2)!);
        return title == null ? match.group(0)! : '[[$title]]';
      });

  static String wikiLinkHref(String title) => Uri(
    scheme: _wikiLinkScheme,
    queryParameters: {'title': title},
  ).toString();

  /// Returns the note title targeted by an internal wiki-link URL.
  static String? wikiLinkTitle(String href) {
    final uri = Uri.tryParse(href);
    if (uri == null || uri.scheme != _wikiLinkScheme) return null;
    final title = uri.queryParameters['title']?.trim();
    return title?.isEmpty ?? true ? null : title;
  }

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

  /// Extracts the portable note-to-note links that participate in backlinks.
  /// Attachment and external Markdown links are ignored by [resolveNoteLink].
  static List<NoteLinkReference> extractNoteLinks(
    String sourceNotePath,
    String markdown,
  ) {
    final links = <NoteLinkReference>[];
    for (final match in _wikiLink.allMatches(markdown)) {
      final title = match.group(1)!.trim();
      if (title.isEmpty) continue;
      links.add(NoteLinkReference(kind: 'wiki', target: title, label: title));
    }
    for (final match in _inlineLinkDestination.allMatches(markdown)) {
      final destination = match.group(2)!;
      final href = destination.startsWith('<') && destination.endsWith('>')
          ? destination.substring(1, destination.length - 1)
          : destination;
      final target = resolveNoteLink(sourceNotePath, href);
      if (target == null) continue;
      final label =
          RegExp(
            r'!?\[([^\]\r\n]*)\]\(',
          ).firstMatch(match.group(1)!)?.group(1)?.trim() ??
          '';
      links.add(
        NoteLinkReference(
          kind: 'markdown',
          target: target,
          label: label.isEmpty ? target : label,
        ),
      );
    }
    return links;
  }

  /// Rewrites relative Markdown links after a note has moved.
  ///
  /// [oldSourcePath] and [newSourcePath] differ when rewriting links inside
  /// the moved note itself. For every other note they are the same, so only
  /// links targeting [movedFromPath] change. External and non-Markdown links
  /// are preserved verbatim.
  static String rebaseNoteLinks(
    String markdown, {
    required String oldSourcePath,
    required String newSourcePath,
    required String movedFromPath,
    required String movedToPath,
  }) => markdown.replaceAllMapped(_inlineLinkDestination, (match) {
    final originalDestination = match.group(2)!;
    final isAngleWrapped =
        originalDestination.startsWith('<') &&
        originalDestination.endsWith('>');
    final href = isAngleWrapped
        ? originalDestination.substring(1, originalDestination.length - 1)
        : originalDestination;
    final target = resolveNoteLink(oldSourcePath, href);
    if (target == null) return match.group(0)!;

    final desiredTarget = target == movedFromPath ? movedToPath : target;
    if (oldSourcePath == newSourcePath && desiredTarget == target) {
      return match.group(0)!;
    }

    final originalUri = Uri.tryParse(href);
    if (originalUri == null) return match.group(0)!;
    final newParent = p.posix.dirname(p.posix.normalize(newSourcePath));
    final relativePath = p.posix.relative(
      desiredTarget,
      from: newParent == '.' ? '' : newParent,
    );
    final rewrittenUri = Uri(
      path: relativePath,
      query: originalUri.hasQuery ? originalUri.query : null,
      fragment: originalUri.hasFragment ? originalUri.fragment : null,
    ).toString();
    final destination = isAngleWrapped ? '<$rewrittenUri>' : rewrittenUri;
    return '${match.group(1)}$destination';
  });

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

  /// Generated summaries are derived metadata, not a competing edit to a
  /// note's content. This lets sync accept the remote note when its only local
  /// difference is the generated `summary:` frontmatter line.
  static bool differsOnlyBySummary(String local, String remote) {
    final localParsed = parse(local);
    final remoteParsed = parse(remote);
    if (localParsed.body != remoteParsed.body) return false;
    return _frontmatterWithoutSummary(localParsed.frontmatter) ==
        _frontmatterWithoutSummary(remoteParsed.frontmatter);
  }

  static String? _frontmatterWithoutSummary(String? frontmatter) {
    if (frontmatter == null) return null;
    return frontmatter
        .split('\n')
        .where((line) => !line.startsWith('summary:'))
        .join('\n');
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
    r'^[ \t]*[-*+][ \t]+\[([ xX])\][ \t]*(.*)$',
    multiLine: true,
  );
  static final _globalTask = RegExp(
    r'^[ \t]*\+[ \t]+\[([ xX])\][ \t]*(.*)$',
    multiLine: true,
  );
  static final _dailyWikiLink = RegExp(r'\[\[(\d{4}-\d{2}-\d{2})\]\]');

  /// Reflect global tasks use a `+` marker. `-` and `*` checkbox rows remain
  /// local to their note and deliberately do not enter the task index.
  static List<({int index, String text, bool completed})> extract(
    String markdown,
  ) => [
    for (final (index, match) in _globalTask.allMatches(markdown).indexed)
      if ((match.group(2)?.trim() ?? '').isNotEmpty)
        (
          index: index,
          text: match.group(2)!.trim(),
          completed: match.group(1)?.toLowerCase() == 'x',
        ),
  ];

  /// Global tasks that carry Reflect's portable daily-note schedule link.
  /// Only valid calendar dates participate; ordinary date-shaped wikilinks do
  /// not accidentally create a relationship with a daily note.
  static List<({int index, String text, bool completed, String date})>
  extractScheduled(String markdown) => [
    for (final task in extract(markdown))
      if (scheduledDate(task.text) case final date?)
        (
          index: task.index,
          text: task.text,
          completed: task.completed,
          date: date,
        ),
  ];

  /// Returns the last valid daily-date wikilink in task text. Scheduling
  /// normalizes tasks to one link, but accepting the last link makes imported
  /// Reflect content deterministic until it is next edited.
  static String? scheduledDate(String text) {
    String? result;
    for (final match in _dailyWikiLink.allMatches(text)) {
      final date = match.group(1)!;
      if (isDailyDate(date)) result = date;
    }
    return result;
  }

  static bool isDailyDate(String value) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
    if (match == null) return false;
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final date = DateTime(year, month, day);
    return date.year == year && date.month == month && date.day == day;
  }

  /// Adds or replaces a global task's daily schedule. Every existing valid
  /// daily-date wikilink on that row is removed so the persisted task has one
  /// unambiguous destination, appended in Reflect's familiar trailing form.
  static String scheduleGlobalAt(String markdown, int taskIndex, String date) {
    if (!isDailyDate(date)) {
      throw ArgumentError.value(date, 'date', 'Use YYYY-MM-DD.');
    }
    var current = 0;
    return markdown.replaceAllMapped(_globalTask, (match) {
      if (current++ != taskIndex) return match.group(0)!;
      final taskText = match
          .group(2)!
          .replaceAllMapped(
            _dailyWikiLink,
            (link) => isDailyDate(link.group(1)!) ? '' : link.group(0)!,
          );
      final normalized = taskText.replaceAll(RegExp(r'\s+'), ' ').trim();
      final prefix = RegExp(
        r'^[ \t]*\+[ \t]+\[[ xX]\][ \t]*',
      ).firstMatch(match.group(0)!)!.group(0)!;
      return '$prefix$normalized [[$date]]';
    });
  }

  /// Removes the task's schedule marker for inline editing. Scheduling has a
  /// dedicated control, so editing task wording cannot accidentally create or
  /// remove a daily-note relationship.
  static String editableText(String text) => text
      .replaceAllMapped(
        _dailyWikiLink,
        (link) => isDailyDate(link.group(1)!) ? '' : link.group(0)!,
      )
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// Replaces a global task's user-facing text while retaining its current
  /// completion state, list indentation, and scheduled daily-note wikilink.
  static String updateGlobalTextAt(
    String markdown,
    int taskIndex,
    String text,
  ) {
    final updatedText = editableText(text);
    if (updatedText.isEmpty) {
      throw ArgumentError.value(text, 'text', 'A task cannot be blank.');
    }
    var current = 0;
    return markdown.replaceAllMapped(_globalTask, (match) {
      if (current++ != taskIndex) return match.group(0)!;
      final prefix = RegExp(
        r'^[ \t]*\+[ \t]+\[[ xX]\][ \t]*',
      ).firstMatch(match.group(0)!)!.group(0)!;
      final date = scheduledDate(match.group(2)!);
      return '$prefix$updatedText${date == null ? '' : ' [[$date]]'}';
    });
  }

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
