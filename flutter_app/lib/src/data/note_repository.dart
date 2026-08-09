import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../domain/markdown.dart';
import '../domain/note.dart';
import '../platform/widget_bridge.dart';
import 'app_database.dart';

/// The Markdown files remain canonical. SQLite is a transactional index and
/// sync journal shared with the legacy Android widget.
class NoteRepository {
  NoteRepository(
    this._db,
    this._notesRoot, {
    Future<void> Function()? onLocalChange,
  }) : _onLocalChange = onLocalChange;

  final AppDatabase _db;
  final Directory _notesRoot;
  final _uuid = const Uuid();
  final Future<void> Function()? _onLocalChange;

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
    final query = _db.select(_db.noteRows)
      ..where((row) => row.isPendingDeletion.equals(false));
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
      innerJoin(
        _db.noteRows,
        _db.noteRows.id.equalsExp(_db.todoEntries.noteId),
      ),
    ])..where(_db.noteRows.isPendingDeletion.equals(false));
    if (!includeCompleted)
      query.where(_db.todoEntries.isCompleted.equals(false));
    query.orderBy([
      OrderingTerm.desc(_db.noteRows.updatedAt),
      OrderingTerm.asc(_db.todoEntries.taskIndex),
    ]);
    return query.watch().map(
      (rows) => rows
          .map(
            (row) => TodoItem(
              noteId: row.readTable(_db.todoEntries).noteId,
              taskIndex: row.readTable(_db.todoEntries).taskIndex,
              text: row.readTable(_db.todoEntries).taskText,
              isCompleted: row.readTable(_db.todoEntries).isCompleted,
              noteTitle: row.readTable(_db.noteRows).title,
            ),
          )
          .toList(),
    );
  }

  Future<Note?> get(String id) async {
    final row = await (_db.select(
      _db.noteRows,
    )..where((note) => note.id.equals(id))).getSingleOrNull();
    return row == null ? null : _toNote(row);
  }

  Future<Note?> findByPath(String path) async {
    final row = await (_db.select(
      _db.noteRows,
    )..where((note) => note.path.equals(path))).getSingleOrNull();
    return row == null ? null : _toNote(row);
  }

  Future<List<Note>> dirtyNotes() async => (await (_db.select(
    _db.noteRows,
  )..where((note) => note.isDirty.equals(true))).get()).map(_toNote).toList();

  Future<void> applyRemote({
    required String path,
    required String sha,
    required String raw,
  }) async {
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
        title: Value(
          parsed.title.isEmpty
              ? p.basenameWithoutExtension(path)
              : parsed.title,
        ),
        path: Value(path),
        rawMarkdown: Value(raw),
        body: Value(parsed.body),
        aliases: Value(_encodeAliases(parsed.aliases)),
        snippet: Value(parsed.snippet ?? MarkdownContract.snippet(parsed.body)),
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
    await (_db.update(
      _db.noteRows,
    )..where((row) => row.id.equals(note.id))).write(
      NoteRowsCompanion(
        lastRemoteSha: Value(sha),
        isDirty: const Value(false),
        pendingRenameFromPath: const Value(null),
        pendingRenameFromSha: const Value(null),
      ),
    );
  }

  Future<void> completeDeletion(Note note) async {
    await _db.transaction(() async {
      await (_db.delete(
        _db.todoEntries,
      )..where((row) => row.noteId.equals(note.id))).go();
      await (_db.delete(
        _db.noteRows,
      )..where((row) => row.id.equals(note.id))).go();
    });
  }

  /// Applies remote deletions without treating unsynced local notes as lost.
  /// Local edits to an already-synced note are retained as conflict copies.
  Future<void> reconcileRemoteRemovals(Set<String> remotePaths) async {
    final localNotes = (await _db.select(_db.noteRows).get()).map(_toNote);
    for (final note in localNotes) {
      if (remotePaths.contains(note.path) ||
          note.isConflict ||
          note.pendingRenameFromPath != null) {
        continue;
      }

      // A note with no remote SHA has never been published, so its absence from
      // the remote tree is expected. A pending unsynced deletion can be
      // completed immediately because there is no remote counterpart to remove.
      if (note.lastRemoteSha == null) {
        if (note.isPendingDeletion) await completeDeletion(note);
        continue;
      }
      if (note.isPendingDeletion) {
        await _removeStoredNote(note);
        continue;
      }
      if (note.isDirty) await preserveConflict(note);
      await _removeStoredNote(note);
    }
  }

  Future<void> setPinned(Note note, bool isPinned) =>
      (_db.update(_db.noteRows)..where((row) => row.id.equals(note.id))).write(
        NoteRowsCompanion(isPinned: Value(isPinned)),
      );

  Future<void> preserveConflict(Note note) async {
    final suffix = DateTime.now().toIso8601String().substring(0, 10);
    final directory = p.dirname(note.path);
    final extension = p.extension(note.path);
    final base = p.basenameWithoutExtension(note.path);
    final conflictPath =
        '${directory == '.' ? '' : '$directory/'}$base (conflict $suffix)$extension';
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
        isPinned: const Value(false),
        lastRemoteSha: const Value.absent(),
        isDirty: const Value(true),
        isPendingDeletion: const Value(false),
        isConflict: const Value(true),
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
      writeFile: true,
    );
  }

  Future<void> _removeStoredNote(Note note) async {
    await completeDeletion(note);
    final file = _file(note.path);
    if (await file.exists()) await file.delete();
  }

  Future<Note> create({
    required String title,
    String body = '',
    String? folder,
  }) async {
    final normalizedTitle = title.trim().isEmpty ? 'Untitled' : title.trim();
    final path = _newPath(normalizedTitle, folder);
    final id = '01${_uuid.v4().replaceAll('-', '').substring(0, 24)}';
    final raw =
        '${MarkdownContract.frontmatter(id)}# $normalizedTitle\n\n${body.trim()}\n';
    final note = await _put(
      NoteRowsCompanion.insert(
        id: id,
        title: normalizedTitle,
        path: path,
        rawMarkdown: raw,
        body: '# $normalizedTitle\n\n${body.trim()}\n',
        aliases: '[]',
        isDaily: false,
        isPinned: const Value(false),
        lastRemoteSha: const Value.absent(),
        isDirty: const Value(true),
        isPendingDeletion: const Value(false),
        isConflict: const Value(false),
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
      writeFile: true,
    );
    _scheduleSync();
    return note;
  }

  Future<Note> getOrCreateToday() async {
    final date = DateTime.now().toIso8601String().substring(0, 10);
    final path = 'daily/$date.md';
    final existing = await (_db.select(
      _db.noteRows,
    )..where((note) => note.path.equals(path))).getSingleOrNull();
    if (existing != null) return _toNote(existing);
    return createDaily(path, date);
  }

  Future<Note> createDaily(String path, String title) async {
    final id = '01${_uuid.v4().replaceAll('-', '').substring(0, 24)}';
    final raw = '${MarkdownContract.frontmatter(id)}# $title\n\n';
    final note = await _put(
      NoteRowsCompanion.insert(
        id: id,
        title: title,
        path: path,
        rawMarkdown: raw,
        body: '# $title\n\n',
        aliases: '[]',
        isDaily: true,
        isPinned: const Value(false),
        lastRemoteSha: const Value.absent(),
        isDirty: const Value(true),
        isPendingDeletion: const Value(false),
        isConflict: const Value(false),
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
      writeFile: true,
    );
    _scheduleSync();
    return note;
  }

  Future<Note> appendToToday(String markdown) async {
    if (markdown.trim().isEmpty)
      throw ArgumentError.value(
        markdown,
        'markdown',
        'A capture cannot be blank',
      );
    final today = await getOrCreateToday();
    return save(
      today,
      title: today.title,
      body: '${today.body.trimRight()}\n\n${markdown.trim()}\n',
    );
  }

  Future<Note> save(
    Note original, {
    required String title,
    required String body,
  }) async {
    final parsed = MarkdownContract.parse(original.rawMarkdown);
    final normalizedTitle = title.trim().isEmpty
        ? original.title
        : title.trim();
    final normalizedBody = body.startsWith('# ')
        ? body
        : '# $normalizedTitle\n\n$body';
    final frontmatter = parsed.frontmatter == null
        ? MarkdownContract.frontmatter(original.id, original.aliases)
        : _ensureId(parsed.frontmatter!, original.id);
    final raw = '---\n$frontmatter\n---\n$normalizedBody';
    final saved = await _put(
      NoteRowsCompanion(
        id: Value(original.id),
        title: Value(normalizedTitle),
        path: Value(original.path),
        rawMarkdown: Value(raw),
        body: Value(normalizedBody),
        aliases: Value(_encodeAliases(parsed.aliases)),
        snippet: Value(
          parsed.snippet ?? MarkdownContract.snippet(normalizedBody),
        ),
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
    _scheduleSync();
    return saved;
  }

  Future<Note> rename(Note note, String requestedPath) async {
    final target = _normalizeMarkdownPath(requestedPath);
    if (target == note.path) return note;
    final existing = await findByPath(target);
    if (existing != null && existing.id != note.id)
      throw StateError('A note already exists at $target.');
    final source = _file(note.path);
    final destination = _file(target);
    await destination.parent.create(recursive: true);
    if (await source.exists()) await source.rename(destination.path);
    final updated = await _put(
      NoteRowsCompanion(
        id: Value(note.id),
        title: Value(note.title),
        path: Value(target),
        rawMarkdown: Value(note.rawMarkdown),
        body: Value(note.body),
        aliases: Value(_encodeAliases(note.aliases)),
        snippet: Value(note.snippet),
        isDaily: Value(note.isDaily),
        isPinned: Value(note.isPinned),
        lastRemoteSha: const Value(null),
        isDirty: const Value(true),
        isPendingDeletion: const Value(false),
        pendingRenameFromPath: Value(note.pendingRenameFromPath ?? note.path),
        pendingRenameFromSha: Value(
          note.pendingRenameFromSha ?? note.lastRemoteSha,
        ),
        isConflict: Value(note.isConflict),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
      writeFile: false,
    );
    _scheduleSync();
    return updated;
  }

  Future<void> delete(Note note) async {
    await _db
        .into(_db.noteRows)
        .insertOnConflictUpdate(
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
    _scheduleSync();
  }

  Future<void> toggleTodo(TodoItem todo) async {
    final note = await get(todo.noteId);
    if (note == null) return;
    await save(
      note,
      title: note.title,
      body: TodoMarkdown.toggleAt(note.body, todo.taskIndex),
    );
  }

  Future<Note> importImage(Note note, File source) async {
    if (!await source.exists())
      throw StateError('The selected image is no longer available.');
    var extension = p.extension(source.path).toLowerCase();
    if (extension.isEmpty || extension.length > 8) extension = '.jpg';
    final assetPath = 'attachments/${_uuid.v4()}$extension';
    final destination = _file(assetPath);
    await destination.parent.create(recursive: true);
    await source.copy(destination.path);
    await _db
        .into(_db.attachments)
        .insertOnConflictUpdate(
          AttachmentsCompanion.insert(
            path: assetPath,
            mimeType: Value(_mimeFor(extension)),
            lastRemoteSha: const Value.absent(),
            isDirty: true,
            updatedAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );
    final markdownPath = attachmentReference(note.path, assetPath);
    return save(
      note,
      title: note.title,
      body: '${note.body.trimRight()}\n\n![]($markdownPath)\n',
    );
  }

  /// Copies an image out of the picker cache without making it part of the
  /// synced attachment set yet. The editor commits these only with Done.
  Future<StagedImage> stageImage(File source) async {
    if (!await source.exists()) {
      throw StateError('The selected image is no longer available.');
    }
    var extension = p.extension(source.path).toLowerCase();
    if (extension.isEmpty || extension.length > 8) extension = '.jpg';
    final id = _uuid.v4();
    final attachmentPath = 'attachments/$id$extension';
    final stagingFile = _file('.editor-staging/$id$extension');
    await stagingFile.parent.create(recursive: true);
    await source.copy(stagingFile.path);
    return StagedImage(
      localPath: stagingFile.path,
      attachmentPath: attachmentPath,
      mimeType: _mimeFor(extension),
    );
  }

  Future<void> commitStagedImages(Iterable<StagedImage> images) async {
    for (final image in images) {
      final source = File(image.localPath);
      if (!await source.exists()) {
        throw StateError('A selected image is no longer available.');
      }
      final destination = _file(image.attachmentPath);
      await destination.parent.create(recursive: true);
      await source.copy(destination.path);
      await _db
          .into(_db.attachments)
          .insertOnConflictUpdate(
            AttachmentsCompanion.insert(
              path: image.attachmentPath,
              mimeType: Value(image.mimeType),
              lastRemoteSha: const Value.absent(),
              isDirty: true,
              updatedAt: DateTime.now().millisecondsSinceEpoch,
            ),
          );
      await source.delete();
    }
  }

  Future<void> discardStagedImages(Iterable<StagedImage> images) async {
    for (final image in images) {
      final file = File(image.localPath);
      if (await file.exists()) await file.delete();
    }
  }

  Future<List<Attachment>> dirtyAttachments() async => (await (_db.select(
    _db.attachments,
  )..where((row) => row.isDirty.equals(true))).get());

  Future<Attachment?> attachment(String path) => (_db.select(
    _db.attachments,
  )..where((row) => row.path.equals(path))).getSingleOrNull();

  Future<List<int>?> attachmentBytes(String path) async {
    final file = _file(path);
    return await file.exists() ? file.readAsBytes() : null;
  }

  Future<void> markAttachmentSynced(String path, String sha) =>
      (_db.update(
        _db.attachments,
      )..where((row) => row.path.equals(path))).write(
        AttachmentsCompanion(
          lastRemoteSha: Value(sha),
          isDirty: const Value(false),
        ),
      );

  Future<void> applyRemoteAttachment({
    required String path,
    required String sha,
    required List<int> bytes,
    String? mimeType,
  }) async {
    final file = _file(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
    await _db
        .into(_db.attachments)
        .insertOnConflictUpdate(
          AttachmentsCompanion.insert(
            path: path,
            mimeType: Value(mimeType),
            lastRemoteSha: Value(sha),
            isDirty: false,
            updatedAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );
  }

  Future<File?> resolveAttachment(String notePath, String destination) async {
    final value = destination.split('#').first.split('?').first.trim();
    if (value.isEmpty ||
        value.contains('://') ||
        value.startsWith('data:') ||
        value.startsWith('file:'))
      return null;
    final base = value.startsWith('attachments/') || value.startsWith('assets/')
        ? ''
        : p.dirname(notePath);
    final resolved = p
        .normalize(p.join(base == '.' ? '' : base, value))
        .replaceAll('\\', '/');
    if (!(resolved.startsWith('attachments/') ||
            resolved.startsWith('assets/')) ||
        resolved.endsWith('.reflect.md'))
      return null;
    final file = _file(resolved);
    return await file.exists() ? file : null;
  }

  String attachmentReference(String notePath, String attachmentPath) {
    final parent = p.dirname(notePath);
    return p
        .relative(attachmentPath, from: parent == '.' ? '' : parent)
        .replaceAll('\\', '/');
  }

  Future<void> updateSnippet(Note note, String snippet) async {
    final plainSnippet = MarkdownContract.plainText(snippet);
    final raw = MarkdownContract.upsertSnippet(
      note.rawMarkdown,
      note.id,
      plainSnippet,
    );
    await _put(
      NoteRowsCompanion(
        id: Value(note.id),
        title: Value(note.title),
        path: Value(note.path),
        rawMarkdown: Value(raw),
        body: Value(note.body),
        aliases: Value(_encodeAliases(note.aliases)),
        snippet: Value(plainSnippet),
        isDaily: Value(note.isDaily),
        isPinned: Value(note.isPinned),
        lastRemoteSha: Value(note.lastRemoteSha),
        isDirty: const Value(true),
        isPendingDeletion: Value(note.isPendingDeletion),
        pendingRenameFromPath: Value(note.pendingRenameFromPath),
        pendingRenameFromSha: Value(note.pendingRenameFromSha),
        isConflict: Value(note.isConflict),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
      writeFile: true,
    );
    _scheduleSync();
  }

  Future<void> importExistingFilesIfNeeded() async {
    final existing = await (_db.select(
      _db.noteRows,
    )..limit(1)).getSingleOrNull();
    if (existing != null) return;
    if (!await _notesRoot.exists()) return;
    await for (final entity in _notesRoot.list(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.md')) continue;
      final relative = p
          .relative(entity.path, from: _notesRoot.path)
          .replaceAll('\\', '/');
      if (relative.endsWith('.reflect.md')) continue;
      final raw = await entity.readAsString();
      final parsed = MarkdownContract.parse(raw);
      final id = MarkdownContract.identityFor(relative, parsed.id);
      final previous = await (_db.select(
        _db.noteRows,
      )..where((note) => note.id.equals(id))).getSingleOrNull();
      await _put(
        NoteRowsCompanion(
          id: Value(id),
          title: Value(
            parsed.title.isEmpty
                ? p.basenameWithoutExtension(relative)
                : parsed.title,
          ),
          path: Value(relative),
          rawMarkdown: Value(raw),
          body: Value(parsed.body),
          aliases: Value(_encodeAliases(parsed.aliases)),
          snippet: Value(
            parsed.snippet ?? MarkdownContract.snippet(parsed.body),
          ),
          isDaily: Value(relative.startsWith('daily/')),
          isPinned: Value(previous?.isPinned ?? false),
          lastRemoteSha: Value(previous?.lastRemoteSha),
          isDirty: Value(previous?.isDirty ?? false),
          isPendingDeletion: Value(previous?.isPendingDeletion ?? false),
          pendingRenameFromPath: Value(previous?.pendingRenameFromPath),
          pendingRenameFromSha: Value(previous?.pendingRenameFromSha),
          isConflict: Value(previous?.isConflict ?? false),
          updatedAt: Value(
            previous?.updatedAt ?? DateTime.now().millisecondsSinceEpoch,
          ),
        ),
        writeFile: false,
      );
    }
  }

  Future<Note> _put(NoteRowsCompanion note, {required bool writeFile}) async {
    if (writeFile) await _write(note.path.value, note.rawMarkdown.value);
    await _db.transaction(() async {
      await _db.into(_db.noteRows).insertOnConflictUpdate(note);
      await (_db.delete(
        _db.todoEntries,
      )..where((row) => row.noteId.equals(note.id.value))).go();
      final tasks = TodoMarkdown.extract(note.body.value);
      for (final task in tasks) {
        await _db
            .into(_db.todoEntries)
            .insert(
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
    if (p.isAbsolute(normalized) ||
        normalized == '..' ||
        normalized.startsWith('../')) {
      throw ArgumentError.value(
        relativePath,
        'relativePath',
        'Path escapes the note store',
      );
    }
    return File(p.join(_notesRoot.path, normalized));
  }

  String _newPath(String title, String? folder) {
    final slug = title
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-|-?$'), '');
    final filename = '${slug.isEmpty ? 'untitled' : slug}.md';
    return folder == null || folder.trim().isEmpty
        ? filename
        : '${folder.trim().replaceAll(RegExp(r'/+$'), '')}/$filename';
  }

  String _normalizeMarkdownPath(String input) {
    final normalized = p.normalize(input.trim()).replaceAll('\\', '/');
    if (normalized.isEmpty ||
        p.isAbsolute(normalized) ||
        normalized == '..' ||
        normalized.startsWith('../')) {
      throw ArgumentError.value(
        input,
        'path',
        'Use a repository-relative path.',
      );
    }
    return normalized.toLowerCase().endsWith('.md')
        ? normalized
        : '$normalized.md';
  }

  void _scheduleSync() {
    unawaited(WidgetBridge.refresh());
    final schedule = _onLocalChange;
    if (schedule != null) unawaited(schedule());
  }

  String _ensureId(String frontmatter, String id) {
    final lines = frontmatter.split('\n');
    final index = lines.indexWhere((line) => line.startsWith('id:'));
    if (index == -1) return 'id: $id\n$frontmatter';
    lines[index] = 'id: $id';
    return lines.join('\n');
  }

  String _encodeAliases(List<String> aliases) =>
      '[${aliases.map((alias) => '"$alias"').join(',')}]';

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
    snippet: row.snippet == null
        ? null
        : MarkdownContract.plainText(row.snippet!),
    aliases: RegExp(
      r'"([^"]+)"',
    ).allMatches(row.aliases).map((match) => match.group(1)!).toList(),
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

class StagedImage {
  const StagedImage({
    required this.localPath,
    required this.attachmentPath,
    required this.mimeType,
  });

  final String localPath;
  final String attachmentPath;
  final String mimeType;
}
