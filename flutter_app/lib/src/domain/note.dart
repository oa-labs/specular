class Note {
  const Note({
    required this.id,
    required this.title,
    required this.path,
    required this.rawMarkdown,
    required this.body,
    required this.summary,
    required this.aliases,
    required this.isDaily,
    required this.isPinned,
    required this.lastRemoteSha,
    required this.isDirty,
    required this.isPendingDeletion,
    required this.pendingRenameFromPath,
    required this.pendingRenameFromSha,
    required this.isConflict,
    this.localRevision = 0,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final String path;
  final String rawMarkdown;
  final String body;
  final String? summary;
  final List<String> aliases;
  final bool isDaily;
  final bool isPinned;
  final String? lastRemoteSha;
  final bool isDirty;
  final bool isPendingDeletion;
  final String? pendingRenameFromPath;
  final String? pendingRenameFromSha;
  final bool isConflict;
  final int localRevision;
  final DateTime updatedAt;
}

class TodoItem {
  const TodoItem({
    required this.noteId,
    required this.taskIndex,
    required this.text,
    required this.isCompleted,
    required this.noteTitle,
  });

  final String noteId;
  final int taskIndex;
  final String text;
  final bool isCompleted;
  final String noteTitle;
}

/// A global task in another note that points at a daily note through a
/// `[[YYYY-MM-DD]]` wikilink.
class ScheduledTaskBacklink {
  const ScheduledTaskBacklink({
    required this.sourceNoteId,
    required this.sourceNoteTitle,
    required this.taskIndex,
    required this.text,
    required this.isCompleted,
  });

  final String sourceNoteId;
  final String sourceNoteTitle;
  final int taskIndex;
  final String text;
  final bool isCompleted;
}

/// An incoming wiki or relative Markdown link resolved by the local index.
class NoteBacklink {
  const NoteBacklink({
    required this.sourceNoteId,
    required this.sourceNoteTitle,
    required this.kind,
    required this.label,
  });

  final String sourceNoteId;
  final String sourceNoteTitle;
  final String kind;
  final String label;
}
