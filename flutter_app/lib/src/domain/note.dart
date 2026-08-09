class Note {
  const Note({
    required this.id,
    required this.title,
    required this.path,
    required this.rawMarkdown,
    required this.body,
    required this.snippet,
    required this.aliases,
    required this.isDaily,
    required this.isPinned,
    required this.lastRemoteSha,
    required this.isDirty,
    required this.isPendingDeletion,
    required this.pendingRenameFromPath,
    required this.pendingRenameFromSha,
    required this.isConflict,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final String path;
  final String rawMarkdown;
  final String body;
  final String? snippet;
  final List<String> aliases;
  final bool isDaily;
  final bool isPinned;
  final String? lastRemoteSha;
  final bool isDirty;
  final bool isPendingDeletion;
  final String? pendingRenameFromPath;
  final String? pendingRenameFromSha;
  final bool isConflict;
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
