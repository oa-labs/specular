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

enum TodoDueDateStyle { wikiLink, emoji }

class TodoDueDate {
  const TodoDueDate({required this.date, required this.style});

  final String date;
  final TodoDueDateStyle style;
}

enum TaskRecurrenceUnit { day, weekday, week, month, year }

class TaskRecurrence {
  const TaskRecurrence({required this.interval, required this.unit});

  final int interval;
  final TaskRecurrenceUnit unit;
}

class TodoTaskMetadata {
  const TodoTaskMetadata({this.dueDate, this.recurrence});

  final TodoDueDate? dueDate;
  final TaskRecurrence? recurrence;
}

class _DueDateMatch {
  const _DueDateMatch({
    required this.start,
    required this.end,
    required this.dueDate,
  });

  final int start;
  final int end;
  final TodoDueDate dueDate;
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
  static final _emojiDueDate = RegExp(r'📅[ \t]+(\d{4}-\d{2}-\d{2})');
  static final _recurrence = RegExp(
    r'🔁[ \t]+every[ \t]+(?:(\d+)[ \t]+)?'
    r'(days?|weekdays?|weeks?|months?|years?)'
    r'(?=$|[ \t.,;:!?()\[\]{}])',
    caseSensitive: false,
  );

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
      if (taskMetadata(task.text).dueDate case final dueDate?)
        (
          index: task.index,
          text: task.text,
          completed: task.completed,
          date: dueDate.date,
        ),
  ];

  /// Returns the last valid task due-date marker in task text. Scheduling
  /// normalizes tasks to one marker, but accepting the last marker makes
  /// imported content deterministic until it is next edited.
  static String? scheduledDate(String text) => taskMetadata(text).dueDate?.date;

  /// Parses the portable task metadata that Specular understands. The last
  /// valid due-date marker wins so imported Markdown with duplicate markers is
  /// deterministic until a later Specular edit normalizes it.
  static TodoTaskMetadata taskMetadata(String text) {
    TodoDueDate? dueDate;
    for (final match in _dueDateMatches(text)) {
      dueDate = match.dueDate;
    }
    TaskRecurrence? recurrence;
    for (final match in _recurrence.allMatches(text)) {
      if (_recurrenceForMatch(match) case final parsed?) recurrence = parsed;
    }
    return TodoTaskMetadata(dueDate: dueDate, recurrence: recurrence);
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

  /// Adds or replaces a global task's due date. Every existing valid due-date
  /// marker on that row is removed so the persisted task has one unambiguous
  /// destination while retaining its existing marker style when present.
  static String scheduleGlobalAt(String markdown, int taskIndex, String date) {
    if (!isDailyDate(date)) {
      throw ArgumentError.value(date, 'date', 'Use YYYY-MM-DD.');
    }
    var current = 0;
    return markdown.replaceAllMapped(_globalTask, (match) {
      if (current++ != taskIndex) return match.group(0)!;
      final metadata = taskMetadata(match.group(2)!);
      final prefix = RegExp(
        r'^[ \t]*\+[ \t]+\[[ xX]\][ \t]*',
      ).firstMatch(match.group(0)!)!.group(0)!;
      return '$prefix${_composeTaskText(
        editableText(match.group(2)!),
        dueDate: TodoDueDate(date: date, style: metadata.dueDate?.style ?? TodoDueDateStyle.wikiLink),
        recurrence: metadata.recurrence,
      )}';
    });
  }

  /// Removes supported task metadata for inline wording edits. Scheduling has
  /// a dedicated control and recurrence is Markdown-first, so editing wording
  /// cannot accidentally create or remove a due-date relationship.
  static String editableText(String text) {
    var result = text;
    for (final match in _dueDateMatches(text).reversed) {
      result = result.replaceRange(match.start, match.end, '');
    }
    result = result.replaceAllMapped(
      _recurrence,
      (match) => _recurrenceForMatch(match) == null ? match.group(0)! : '',
    );
    return result.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Replaces a global task's user-facing text while retaining its current
  /// completion state, list indentation, due date, and recurrence metadata.
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
      final metadata = taskMetadata(match.group(2)!);
      return '$prefix${_composeTaskText(updatedText, dueDate: metadata.dueDate, recurrence: metadata.recurrence)}';
    });
  }

  /// Toggles a task by its index within the global `+` task list.
  static String toggleGlobalAt(String markdown, int taskIndex) {
    var current = 0;
    return markdown.replaceAllMapped(_globalTask, (match) {
      if (current++ != taskIndex) return match.group(0)!;
      return _toggleGlobalTaskMatch(match);
    });
  }

  /// Returns the next due date that a global completion will create, if any.
  /// Callers use this to ensure the destination daily note exists before the
  /// source Markdown changes.
  static String? nextScheduledDateOnGlobalCompletion(
    String markdown,
    int taskIndex,
  ) {
    var current = 0;
    for (final match in _globalTask.allMatches(markdown)) {
      if (current++ != taskIndex) continue;
      return _nextDateForUncheckedTask(match);
    }
    return null;
  }

  /// Toggles a checkbox by its index among every checkbox in a note. This is
  /// used by the note preview, where local and global checkboxes are both
  /// interactive.
  static String toggleCheckboxAt(String markdown, int taskIndex) {
    var current = 0;
    return markdown.replaceAllMapped(_checkbox, (match) {
      if (current++ != taskIndex) return match.group(0)!;
      final isGlobal = RegExp(
        r'^[ \t]*\+[ \t]+\[[ xX]\]',
      ).hasMatch(match.group(0)!);
      return isGlobal ? _toggleGlobalTaskMatch(match) : _toggleMatch(match);
    });
  }

  /// Equivalent to [nextScheduledDateOnGlobalCompletion] for the mixed
  /// checkbox index used by note previews.
  static String? nextScheduledDateOnCheckboxCompletion(
    String markdown,
    int taskIndex,
  ) {
    var current = 0;
    for (final match in _checkbox.allMatches(markdown)) {
      if (current++ != taskIndex) continue;
      final isGlobal = RegExp(
        r'^[ \t]*\+[ \t]+\[[ xX]\]',
      ).hasMatch(match.group(0)!);
      return isGlobal ? _nextDateForUncheckedTask(match) : null;
    }
    return null;
  }

  /// Advances a valid, dated recurrence exactly once. This is exposed for
  /// tests and keeps date calculation shared by every completion surface.
  static String nextOccurrenceDate(String date, TaskRecurrence recurrence) {
    if (!isDailyDate(date)) {
      throw ArgumentError.value(date, 'date', 'Use YYYY-MM-DD.');
    }
    final source = DateTime.parse(date);
    final next = switch (recurrence.unit) {
      TaskRecurrenceUnit.day => source.add(Duration(days: recurrence.interval)),
      TaskRecurrenceUnit.week => source.add(
        Duration(days: 7 * recurrence.interval),
      ),
      TaskRecurrenceUnit.weekday => _addWeekdays(source, recurrence.interval),
      TaskRecurrenceUnit.month => _addMonths(source, recurrence.interval),
      TaskRecurrenceUnit.year => _addMonths(source, 12 * recurrence.interval),
    };
    return '${next.year.toString().padLeft(4, '0')}-'
        '${next.month.toString().padLeft(2, '0')}-'
        '${next.day.toString().padLeft(2, '0')}';
  }

  static String _toggleGlobalTaskMatch(Match match) {
    if (match.group(1)?.toLowerCase() == 'x') return _toggleMatch(match);
    final metadata = taskMetadata(match.group(2)!);
    if (metadata.dueDate == null || metadata.recurrence == null) {
      return _toggleMatch(match);
    }
    final prefix = RegExp(
      r'^[ \t]*\+[ \t]+\[[ xX]\][ \t]*',
    ).firstMatch(match.group(0)!)!.group(0)!;
    final completed = match.group(0)!.replaceFirst('[ ]', '[x]');
    final nextDate = nextOccurrenceDate(
      metadata.dueDate!.date,
      metadata.recurrence!,
    );
    final nextTask = _composeTaskText(
      editableText(match.group(2)!),
      dueDate: TodoDueDate(date: nextDate, style: metadata.dueDate!.style),
      recurrence: metadata.recurrence,
    );
    return '$completed\n$prefix$nextTask';
  }

  static String? _nextDateForUncheckedTask(Match match) {
    if (match.group(1)?.toLowerCase() == 'x') return null;
    final metadata = taskMetadata(match.group(2)!);
    if (metadata.dueDate == null || metadata.recurrence == null) return null;
    return nextOccurrenceDate(metadata.dueDate!.date, metadata.recurrence!);
  }

  static String _toggleMatch(Match match) {
    final marker = match.group(1)?.toLowerCase() == 'x' ? ' ' : 'x';
    return match.group(0)!.replaceFirst(RegExp(r'\[.\]'), '[$marker]');
  }

  static List<_DueDateMatch> _dueDateMatches(String text) {
    final matches = <_DueDateMatch>[];
    for (final match in _dailyWikiLink.allMatches(text)) {
      final date = match.group(1)!;
      if (!isDailyDate(date)) continue;
      matches.add(
        _DueDateMatch(
          start: match.start,
          end: match.end,
          dueDate: TodoDueDate(date: date, style: TodoDueDateStyle.wikiLink),
        ),
      );
    }
    for (final match in _emojiDueDate.allMatches(text)) {
      final date = match.group(1)!;
      if (!isDailyDate(date)) continue;
      matches.add(
        _DueDateMatch(
          start: match.start,
          end: match.end,
          dueDate: TodoDueDate(date: date, style: TodoDueDateStyle.emoji),
        ),
      );
    }
    matches.sort((left, right) => left.start.compareTo(right.start));
    return matches;
  }

  static TaskRecurrenceUnit? _recurrenceUnit(String value) =>
      switch (value.toLowerCase()) {
        'day' || 'days' => TaskRecurrenceUnit.day,
        'weekday' || 'weekdays' => TaskRecurrenceUnit.weekday,
        'week' || 'weeks' => TaskRecurrenceUnit.week,
        'month' || 'months' => TaskRecurrenceUnit.month,
        'year' || 'years' => TaskRecurrenceUnit.year,
        _ => null,
      };

  static TaskRecurrence? _recurrenceForMatch(Match match) {
    final interval = int.tryParse(match.group(1) ?? '1') ?? 0;
    final unit = _recurrenceUnit(match.group(2)!);
    return interval > 0 && unit != null
        ? TaskRecurrence(interval: interval, unit: unit)
        : null;
  }

  static String _composeTaskText(
    String text, {
    TodoDueDate? dueDate,
    TaskRecurrence? recurrence,
  }) {
    final parts = <String>[text.trim()];
    if (recurrence != null) parts.add(_formatRecurrence(recurrence));
    if (dueDate != null) {
      parts.add(
        dueDate.style == TodoDueDateStyle.emoji
            ? '📅 ${dueDate.date}'
            : '[[${dueDate.date}]]',
      );
    }
    return parts.where((part) => part.isNotEmpty).join(' ');
  }

  static String _formatRecurrence(TaskRecurrence recurrence) {
    final unit = switch (recurrence.unit) {
      TaskRecurrenceUnit.day => 'day',
      TaskRecurrenceUnit.weekday => 'weekday',
      TaskRecurrenceUnit.week => 'week',
      TaskRecurrenceUnit.month => 'month',
      TaskRecurrenceUnit.year => 'year',
    };
    return recurrence.interval == 1
        ? '🔁 every $unit'
        : '🔁 every ${recurrence.interval} ${unit}s';
  }

  static DateTime _addWeekdays(DateTime source, int count) {
    var result = source;
    var remaining = count;
    while (remaining > 0) {
      result = result.add(const Duration(days: 1));
      if (result.weekday <= DateTime.friday) remaining--;
    }
    return result;
  }

  static DateTime _addMonths(DateTime source, int months) {
    final target = DateTime(source.year, source.month + months, 1);
    final lastDay = DateTime(target.year, target.month + 1, 0).day;
    return DateTime(
      target.year,
      target.month,
      source.day.clamp(1, lastDay).toInt(),
    );
  }
}
