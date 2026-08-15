import 'dart:math' as math;

import 'markdown.dart';
import 'note.dart';

/// Limits a full-text query to the fields a user wants to search.
enum NoteSearchScope { all, title, body }

/// A user-entered search query.
///
/// Unquoted words are prefix terms: `meet` finds `meeting`. Quoted phrases
/// preserve word order: `"design review"` only finds those adjacent words.
/// Terms are combined with AND so every term must match the selected scope.
class NoteSearchQuery {
  NoteSearchQuery(this.text, {this.scope = NoteSearchScope.all})
    : _clauses = _parse(text);

  final String text;
  final NoteSearchScope scope;
  final List<_SearchClause> _clauses;

  bool get isEmpty => _clauses.isEmpty;

  /// Text fragments shown as highlights in titles and result excerpts.
  List<String> get highlightTerms => [
    for (final clause in _clauses) clause.source,
  ];

  static List<_SearchClause> _parse(String input) {
    final clauses = <_SearchClause>[];
    final matcher = RegExp(r'"([^"]+)"|(\S+)');
    for (final match in matcher.allMatches(input)) {
      final phrase = match.group(1);
      final source = (phrase ?? match.group(2)!).trim();
      final normalized = _normalize(source);
      if (normalized.isEmpty) continue;
      clauses.add(
        _SearchClause(
          source: source,
          normalized: normalized,
          isPhrase: phrase != null,
        ),
      );
    }
    return clauses;
  }
}

class _SearchClause {
  const _SearchClause({
    required this.source,
    required this.normalized,
    required this.isPhrase,
  });

  final String source;
  final String normalized;
  final bool isPhrase;
}

/// A note matched by [rankNotes], with the data needed to render its result.
class NoteSearchResult {
  const NoteSearchResult({
    required this.note,
    required this.score,
    required this.excerpt,
  });

  final Note note;
  final int score;
  final String? excerpt;
}

/// Ranks [notes] using token-aware full-text matching.
///
/// This deliberately runs above the SQLite index so Android and macOS retain
/// identical behavior without depending on an optional SQLite FTS extension.
/// A title hit, an exact phrase, and a match near the start of a field are
/// ranked above ordinary body-term hits. Empty searches return recent notes.
List<NoteSearchResult> rankNotes(Iterable<Note> notes, NoteSearchQuery query) {
  final results = <NoteSearchResult>[];
  for (final note in notes) {
    final title = _SearchField(note.title);
    final bodyText = MarkdownContract.plainText(
      note.body.replaceFirst(RegExp(r'^#\s+[^\n]*(?:\n|$)'), ''),
    );
    final body = _SearchField(bodyText);

    if (query.isEmpty) {
      results.add(NoteSearchResult(note: note, score: 0, excerpt: null));
      continue;
    }

    final fields = switch (query.scope) {
      NoteSearchScope.all => [title, body],
      NoteSearchScope.title => [title],
      NoteSearchScope.body => [body],
    };
    if (!query._clauses.every(
      (clause) => fields.any((field) => field.matches(clause)),
    )) {
      continue;
    }

    var score = 0;
    for (final clause in query._clauses) {
      score += title.score(clause, weight: 12);
      score += body.score(clause, weight: 3);
    }
    if (title.normalized.startsWith(_normalize(query.text))) score += 240;
    if (title.normalized == _normalize(query.text)) score += 400;
    results.add(
      NoteSearchResult(
        note: note,
        score: score,
        excerpt: _excerpt(bodyText, query),
      ),
    );
  }
  results.sort((a, b) {
    final byScore = b.score.compareTo(a.score);
    if (byScore != 0) return byScore;
    final byUpdated = b.note.updatedAt.compareTo(a.note.updatedAt);
    if (byUpdated != 0) return byUpdated;
    return a.note.title.toLowerCase().compareTo(b.note.title.toLowerCase());
  });
  return results;
}

class _SearchField {
  _SearchField(String source)
    : normalized = _normalize(source),
      tokens = _normalize(source).split(' ').where((token) => token.isNotEmpty);

  final String normalized;
  final Iterable<String> tokens;

  bool matches(_SearchClause clause) => clause.isPhrase
      ? normalized.contains(clause.normalized)
      : tokens.any((token) => token.startsWith(clause.normalized));

  int score(_SearchClause clause, {required int weight}) {
    if (clause.isPhrase) {
      final count = _occurrences(normalized, clause.normalized);
      if (count == 0) return 0;
      final nearStart = normalized.startsWith(clause.normalized)
          ? weight * 8
          : 0;
      return (count * weight * 6) + nearStart;
    }
    var score = 0;
    for (final token in tokens) {
      if (token == clause.normalized) {
        score += weight * 3;
      } else if (token.startsWith(clause.normalized)) {
        score += weight * 2;
      }
    }
    if (normalized.startsWith(clause.normalized)) score += weight * 4;
    return score;
  }
}

String _normalize(String value) => value
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
    .trim()
    .replaceAll(RegExp(r'\s+'), ' ');

int _occurrences(String haystack, String needle) {
  var count = 0;
  var index = haystack.indexOf(needle);
  while (index >= 0) {
    count++;
    index = haystack.indexOf(needle, index + needle.length);
  }
  return count;
}

String? _excerpt(String body, NoteSearchQuery query) {
  final collapsed = body.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (collapsed.isEmpty) return null;
  final lower = collapsed.toLowerCase();
  var hit = -1;
  for (final term in query.highlightTerms) {
    final index = lower.indexOf(term.toLowerCase());
    if (index >= 0 && (hit < 0 || index < hit)) hit = index;
  }
  if (hit < 0) {
    return collapsed.length <= 150
        ? collapsed
        : '${collapsed.substring(0, 149)}…';
  }

  const radius = 72;
  final start = math.max(0, hit - radius);
  final end = math.min(collapsed.length, hit + radius);
  final prefix = start == 0 ? '' : '…';
  final suffix = end == collapsed.length ? '' : '…';
  return '$prefix${collapsed.substring(start, end).trim()}$suffix';
}

/// Returns non-overlapping case-insensitive match ranges for result styling.
List<(int start, int end)> searchHighlightRanges(
  String text,
  NoteSearchQuery query,
) {
  final terms =
      query.highlightTerms.where((term) => term.isNotEmpty).toSet().toList()
        ..sort((a, b) => b.length.compareTo(a.length));
  final lower = text.toLowerCase();
  final ranges = <(int start, int end)>[];
  for (final term in terms) {
    final needle = term.toLowerCase();
    var start = lower.indexOf(needle);
    while (start >= 0) {
      final end = start + needle.length;
      final overlaps = ranges.any(
        (range) => start < range.$2 && end > range.$1,
      );
      if (!overlaps) ranges.add((start, end));
      start = lower.indexOf(needle, end);
    }
  }
  ranges.sort((a, b) => a.$1.compareTo(b.$1));
  return ranges;
}
