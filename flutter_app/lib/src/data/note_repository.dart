import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../domain/markdown.dart';
import '../domain/note.dart';
import 'app_database.dart';

/// The Markdown files remain canonical. SQLite is a transactional index and
/// sync journal shared with the legacy Android widget.
class NoteRepository {
  NoteRepository(this._db, this._notesRoot);

  final AppDatabase _db;
  final Directory _notesRoot;
  final _uuid = const Uuid();

  Stream<List<Note>> watchNotes() {
    final query = _db.select(_db.noteRows)
      ..where((row) => row.isPendingDeletion.equals(false))
      ..orderBy([
        (row) => OrderingTerm.desc(row.isDaily),
        (row) => OrderingTerm.desc(row.updatedAt),
      ]);
    return query.watch().map((rows) => rows.map(_toNote).toList());
  }

  Stream<List<Note>> search(String input) {
    final query = _db.select(_db.noteRows)..where((row) => row.isPendingDeletion.equals(false));
    final term = input.trim();
    if (term.isNotEmpty) {
      final pattern = '%${term.replaceAll('%', '\\%').replaceAll('_', '\\_')}%';
      query.where((row) => row.title.like(pattern) | row.body.like(pattern));
    }
    query.orderBy([(row) => OrderingTerm.desc(row.updatedAt)]);
    return query.watch().map((rows) => rows.map(_toNote).toList());
  }

  Stream<List<TodoItem>> watchTodos({bool includeCompleted = false}) {
    final query = _db.select(_db.todoEntries).join([
      innerJoin(_db.noteRows, _db.noteRows.id.equalsExp(_db.todoEntries.noteId)),
    ])
      ..where(_db.noteRows.isPendingDeletion.equals(false));
    if (!includeCompleted) query.where(_db.todoEntries.isCompleted.equals(false));
    query.orderBy([
      OrderingTerm.desc(_db.noteRows.updatedAt),
      OrderingTerm.asc(_db.todoEntries.taskIndex),
    ]);
    return query.watch().map((rows) => rows
        .map(
          (row) => TodoItem(
            noteId: row.readTable(_db.todoEntries).noteId,
            taskIndex: row.readTable(_db.todoEntries).taskIndex,
            text: row.readTable(_db.todoEntries).taskText,
            isCompleted: row.readTable(_db.todoEntries).isCompleted,
            noteTitle: row.readTable(_db.noteRows).title,
          ),
        )
        .toList());
  }

  Future<Note?> get(String id) async {
    final row = await (_db.select(_db.noteRows)..where((note) => note.id.equals(id))).getSingleOrNull();
    return row == null ? null : _toNote(row);
  }

  Future<Note?> findByPath(String path) async {
    final row = await (_db.select(_db.noteRows)..where((note) => note.path.equals(path))).getSingleOrNull();
    return row == null ? null : _toNote(row);
  }

  Future<List<Note>> dirtyNotes() async =>
      (await (_db.select(_db.noteRows)..where((note) => note.isDirty.equals(true))).get()).map(_toNote).toList();

  Future<void> applyRemote({required String path, required String sha, required String raw}) async {
    final parsed = MarkdownContract.parse(raw);
    final id = MarkdownContract.identityFor(path, parsed.id);
    final previous = await get(id);
    if (previous != null && previous.path != path) {
      final oldFile = _file(previous.path);
      if (await oldFile.exists()) await oldFile.delete();
    }
    await _put(
      NoteRowsCompanion(
        id: Value(id),
        title: Value(parsed.title.isEmpty ? p.basenameWithoutExtension(path) : parsed.title),
        path: Value(path),
        rawMarkdown: Value(raw),
        body: Value(parsed.body),
        aliases: Value(_encodeAliases(parsed.aliases)),
        snippet: Value(MarkdownContract.snippet(parsed.body)),
        isDaily: Value(path.startsWith('daily/')),
        isPinned: Value(previous?.isPinned ?? false),
        lastRemoteSha: Value(sha),
        isDirty: const Value(false),
        isPendingDeletion: const Value(false),
        pendingRenameFromPath: const Value.absent(),
        pendingRenameFromSha: const Value.absent(),
        isConflict: const Value(false),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
      writeFile: true,
    );
  }

  Future<void> markSynced(Note note, String sha) async {
    await (_db.update(_db.noteRows)..where((row) => row.id.equals(note.id))).write(
      NoteRowsCompanion(
        lastRemoteSha: Value(sha),
        isDirty: const Value(false),
        pendingRenameFromPath: const Value.absent(),
        pendingRenameFromSha: const Value.absent(),
      ),
    );
  }

  Future<void> completeDeletion(Note note) async {
    await _db.transaction(() async {
      await (_db.delete(_db.todoEntries)..where((row) => row.noteId.equals(note.id))).go();
      await (_db.delete(_db.noteRows)..where((row) => row.id.equals(note.id))).go();
    });
  }

  Future<void> preserveConflict(Note note) async {
    final suffix = DateTime.now().toIso8601String().substring(0, 10);
    final directory = p.dirname(note.path);
    final extension = p.extension(note.path);
    final base = p.basenameWithoutExtension(note.path);
    final conflictPath = '${directory == '.' ? '' : '$directory/'}$base (conflict $suffix)$extension';
    final conflictId = '01${_uuid.v4().replaceAll('-', '').substring(0, 24)}';
    final raw = '${MarkdownContract.frontmatter(conflictId)}${note.body}';
    await _put(
      NoteRowsCompanion.insert(
        id: conflictId,
        title: '${note.title} (conflict)',
        path: conflictPath,
        rawMarkdown: raw,
        body: note.body,
        aliases: _encodeAliases(note.aliases),
        isDaily: false,
        lastRemoteSha: const Value.absent(),
        isDirty: const Value(true),
        isConflict: const Value(true),
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
      writeFile: true,
    );
  }

  Future<Note> create({required String title, String body = '', String? folder}) async {
    final normalizedTitle = title.trim().isEmpty ? 'Untitled' : title.trim();
    final path = _newPath(normalizedTitle, folder);
    final id = '01${_uuid.v4().replaceAll('-', '').substring(0, 24)}';
    final raw = '${MarkdownContract.frontmatter(id)}# $normalizedTitle\n\n${body.trim()}\n';
    final note = await _put(
      NoteRowsCompanion.insert(
        id: id,
        title: normalizedTitle,
        path: path,
        rawMarkdown: raw,
        body: '# $normalizedTitle\n\n${body.trim()}\n',
        aliases: '[]',
        isDaily: false,
        lastRemoteSha: const Value.absent(),
        isDirty: const Value(true),
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
      writeFile: true,
    );
    return note;
  }

  Future<Note> getOrCreateToday() async {
    final date = DateTime.now().toIso8601String().substring(0, 10);
    final path = 'daily/$date.md';
    final existing = await (_db.select(_db.noteRows)..where((note) => note.path.equals(path))).getSingleOrNull();
    if (existing != null) return _toNote(existing);
    return createDaily(path, date);
  }

  Future<Note> createDaily(String path, String title) async {
    final id = '01${_uuid.v4().replaceAll('-', '').substring(0, 24)}';
    final raw = '${MarkdownContract.frontmatter(id)}# $title\n\n';
    return _put(
      NoteRowsCompanion.insert(
        id: id,
        title: title,
        path: path,
        rawMarkdown: raw,
        body: '# $title\n\n',
        aliases: '[]',
        isDaily: true,
        lastRemoteSha: const Value.absent(),
        isDirty: const Value(true),
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
      writeFile: true,
    );
  }

  Future<Note> appendToToday(String markdown) async {
    if (markdown.trim().isEmpty) throw ArgumentError.value(markdown, 'markdown', 'A capture cannot be blank');
    final today = await getOrCreateToday();
    return save(today, title: today.title, body: '${today.body.trimRight()}\n\n${markdown.trim()}\n');
  }

  Future<Note> save(Note original, {required String title, required String body}) async {
    final parsed = MarkdownContract.parse(original.rawMarkdown);
    final normalizedTitle = title.trim().isEmpty ? original.title : title.trim();
    final normalizedBody = body.startsWith('# ') ? body : '# $normalizedTitle\n\n$body';
    final frontmatter = parsed.frontmatter == null
        ? MarkdownContract.frontmatter(original.id, original.aliases)
        : _ensureId(parsed.frontmatter!, original.id);
    final raw = '---\n$frontmatter\n---\n$normalizedBody';
    return _put(
      NoteRowsCompanion(
        id: Value(original.id),
        title: Value(normalizedTitle),
        path: Value(original.path),
        rawMarkdown: Value(raw),
        body: Value(normalizedBody),
        aliases: Value(_encodeAliases(parsed.aliases)),
        snippet: Value(MarkdownContract.snippet(normalizedBody)),
        isDaily: Value(original.isDaily),
        isPinned: Value(original.isPinned),
        lastRemoteSha: Value(original.lastRemoteSha),
        isDirty: const Value(true),
        isPendingDeletion: Value(original.isPendingDeletion),
        pendingRenameFromPath: Value(original.pendingRenameFromPath),
        pendingRenameFromSha: Value(original.pendingRenameFromSha),
        isConflict: Value(original.isConflict),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
      writeFile: true,
    );
  }

  Future<void> delete(Note note) async {
    await _db.into(_db.noteRows).insertOnConflictUpdate(
          NoteRowsCompanion(
            id: Value(note.id),
            title: Value(note.title),
            path: Value(note.path),
            rawMarkdown: Value(note.rawMarkdown),
            body: Value(note.body),
            aliases: Value(_encodeAliases(note.aliases)),
            isDaily: Value(note.isDaily),
            isPinned: Value(note.isPinned),
            lastRemoteSha: Value(note.lastRemoteSha),
            isDirty: const Value(true),
            isPendingDeletion: const Value(true),
            pendingRenameFromPath: Value(note.pendingRenameFromPath),
            pendingRenameFromSha: Value(note.pendingRenameFromSha),
            isConflict: Value(note.isConflict),
            updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
          ),
        );
    final file = _file(note.path);
    if (await file.exists()) await file.delete();
  }

  Future<void> toggleTodo(TodoItem todo) async {
    final note = await get(todo.noteId);
    if (note == null) return;
    await save(note, title: note.title, body: TodoMarkdown.toggleAt(note.body, todo.taskIndex));
  }

  Future<Note> importImage(Note note, File source) async {
    if (!await source.exists()) throw StateError('The selected image is no longer available.');
    var extension = p.extension(source.path).toLowerCase();
    if (extension.isEmpty || extension.length > 8) extension = '.jpg';
    final assetPath = 'attachments/${_uuid.v4()}$extension';
    final destination = _file(assetPath);
    await destination.parent.create(recursive: true);
    await source.copy(destination.path);
    await _db.into(_db.attachments).insertOnConflictUpdate(
          AttachmentsCompanion.insert(
            path: assetPath,
            mimeType: Value(_mimeFor(extension)),
            lastRemoteSha: const Value.absent(),
            isDirty: true,
            updatedAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );
    final fromFolder = p.dirname(note.path);
    final markdownPath = p.relative(assetPath, from: fromFolder == '.' ? '' : fromFolder).replaceAll('\\', '/');
    return save(note, title: note.title, body: '${note.body.trimRight()}\n\n![]($markdownPath)\n');
  }

  Future<void> importExistingFilesIfNeeded() async {
    final existing = await (_db.select(_db.noteRows)..limit(1)).getSingleOrNull();
    if (existing != null) return;
    if (!await _notesRoot.exists()) return;
    await for (final entity in _notesRoot.list(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.md')) continue;
      final relative = p.relative(entity.path, from: _notesRoot.path).replaceAll('\\', '/');
      if (relative.endsWith('.reflect.md')) continue;
      final raw = await entity.readAsString();
      final parsed = MarkdownContract.parse(raw);
      final id = MarkdownContract.identityFor(relative, parsed.id);
      final previous = await (_db.select(_db.noteRows)..where((note) => note.id.equals(id))).getSingleOrNull();
      await _put(
        NoteRowsCompanion(
          id: Value(id),
          title: Value(parsed.title.isEmpty ? p.basenameWithoutExtension(relative) : parsed.title),
          path: Value(relative),
          rawMarkdown: Value(raw),
          body: Value(parsed.body),
          aliases: Value(_encodeAliases(parsed.aliases)),
          snippet: Value(MarkdownContract.snippet(parsed.body)),
          isDaily: Value(relative.startsWith('daily/')),
          isPinned: Value(previous?.isPinned ?? false),
          lastRemoteSha: Value(previous?.lastRemoteSha),
          isDirty: Value(previous?.isDirty ?? false),
          isPendingDeletion: Value(previous?.isPendingDeletion ?? false),
          pendingRenameFromPath: Value(previous?.pendingRenameFromPath),
          pendingRenameFromSha: Value(previous?.pendingRenameFromSha),
          isConflict: Value(previous?.isConflict ?? false),
          updatedAt: Value(previous?.updatedAt ?? DateTime.now().millisecondsSinceEpoch),
        ),
        writeFile: false,
      );
    }
  }

  Future<Note> _put(NoteRowsCompanion note, {required bool writeFile}) async {
    if (writeFile) await _write(note.path.value, note.rawMarkdown.value);
    await _db.transaction(() async {
      await _db.into(_db.noteRows).insertOnConflictUpdate(note);
      await (_db.delete(_db.todoEntries)..where((row) => row.noteId.equals(note.id.value))).go();
      final tasks = TodoMarkdown.extract(note.body.value);
      for (final task in tasks) {
        await _db.into(_db.todoEntries).insert(
              TodoEntriesCompanion.insert(
                noteId: note.id.value,
                taskIndex: task.index,
                taskText: task.text,
                isCompleted: task.completed,
              ),
            );
      }
    });
    return (await get(note.id.value))!;
  }

  Future<void> _write(String relativePath, String contents) async {
    final file = _file(relativePath);
    await file.parent.create(recursive: true);
    await file.writeAsString(contents);
  }

  File _file(String relativePath) {
    final normalized = p.normalize(relativePath);
    if (p.isAbsolute(normalized) || normalized == '..' || normalized.startsWith('../')) {
      throw ArgumentError.value(relativePath, 'relativePath', 'Path escapes the note store');
    }
    return File(p.join(_notesRoot.path, normalized));
  }

  String _newPath(String title, String? folder) {
    final slug = title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-|-?$'), '');
    final filename = '${slug.isEmpty ? 'untitled' : slug}.md';
    return folder == null || folder.trim().isEmpty ? filename : '${folder.trim().replaceAll(RegExp(r'/+$'), '')}/$filename';
  }

  String _ensureId(String frontmatter, String id) {
    final lines = frontmatter.split('\n');
    final index = lines.indexWhere((line) => line.startsWith('id:'));
    if (index == -1) return 'id: $id\n$frontmatter';
    lines[index] = 'id: $id';
    return lines.join('\n');
  }

  String _encodeAliases(List<String> aliases) => '[${aliases.map((alias) => '"$alias"').join(',')}]';

  String _mimeFor(String extension) => switch (extension) {
        '.png' => 'image/png',
        '.gif' => 'image/gif',
        '.webp' => 'image/webp',
        _ => 'image/jpeg',
      };

  Note _toNote(NoteRow row) => Note(
        id: row.id,
        title: row.title,
        path: row.path,
        rawMarkdown: row.rawMarkdown,
        body: row.body,
        aliases: RegExp(r'"([^"]+)"').allMatches(row.aliases).map((match) => match.group(1)!).toList(),
        isDaily: row.isDaily,
        isPinned: row.isPinned,
        lastRemoteSha: row.lastRemoteSha,
        isDirty: row.isDirty,
        isPendingDeletion: row.isPendingDeletion,
        pendingRenameFromPath: row.pendingRenameFromPath,
        pendingRenameFromSha: row.pendingRenameFromSha,
        isConflict: row.isConflict,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(row.updatedAt),
      );
}
