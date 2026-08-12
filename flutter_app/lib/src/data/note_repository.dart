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
  NoteRepository(this._db, this._notesRoot, {this._onLocalChange});

  final AppDatabase _db;
  final Directory _notesRoot;
  final _uuid = const Uuid();
  final Future<void> Function()? _onLocalChange;

  /// The canonical Markdown library, exposed read-only for portable backup.
  Directory get notesRoot => _notesRoot;

  Future<List<Note>> notesForBackup() async =>
      (await (_db.select(_db.noteRows)
                ..where((row) => row.isPendingDeletion.equals(false))
                ..orderBy([(row) => OrderingTerm.asc(row.path)]))
              .get())
          .map(_toNote)
          .toList();

  Stream<List<Note>> watchNotes() {
    final query = _db.select(_db.noteRows)
      ..where((row) => row.isPendingDeletion.equals(false))
      ..orderBy([
        (row) => OrderingTerm.desc(row.isDaily),
        (row) => OrderingTerm.desc(row.updatedAt),
      ]);
    return query.watch().map((rows) => rows.map(_toNote).toList());
  }

  Future<bool> hasLocalNotes() async =>
      await (_db.select(_db.noteRows)..limit(1)).getSingleOrNull() != null;

  Future<bool> hasPendingSyncChanges() async {
    final dirtyNote =
        await (_db.select(_db.noteRows)
              ..where((row) => row.isDirty.equals(true))
              ..limit(1))
            .getSingleOrNull();
    if (dirtyNote != null) return true;
    return await (_db.select(_db.attachments)
              ..where((row) => row.isDirty.equals(true))
              ..limit(1))
            .getSingleOrNull() !=
        null;
  }

  /// Reads the durable lease rather than in-memory sync state, so a foreground
  /// Flutter engine can see work that is running in WorkManager's isolate.
  Future<bool> isGitHubSyncActive() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    return await (_db.select(_db.syncLeases)
              ..where(
                (lease) =>
                    lease.scope.equals('github') &
                    lease.expiresAt.isBiggerThanValue(now),
              )
              ..limit(1))
            .getSingleOrNull() !=
        null;
  }

  /// Removes only the local mirror and index. The selected GitHub repository
  /// and its contents are never modified. A lease prevents clearing while a
  /// foreground or background sync owns the same database.
  Future<void> clearLocalCache() async {
    final lease = await acquireSyncLease(
      owner: 'cache-clear-${DateTime.now().microsecondsSinceEpoch}',
    );
    if (lease == null) {
      throw StateError('Wait for the current sync to finish before clearing.');
    }
    try {
      if (await _notesRoot.exists()) {
        for (final entry in await _notesRoot.list().toList()) {
          await entry.delete(recursive: true);
        }
      }
      await _notesRoot.create(recursive: true);
      await _db.transaction(() async {
        await _db.delete(_db.todoEntries).go();
        await _db.delete(_db.todoIndexStates).go();
        await _db.delete(_db.attachments).go();
        await _db.delete(_db.syncOperations).go();
        await _db.delete(_db.noteRows).go();
      });
    } finally {
      await releaseSyncLease(lease);
    }
  }

  /// Restores a validated portable backup into an empty, disconnected library.
  /// Restored content is local-only and marked dirty so a later, explicit
  /// GitHub setup can publish it normally.
  Future<void> restorePortableBackup(
    Directory source, {
    required Map<String, bool> pinnedByPath,
  }) async {
    if (await hasLocalNotes()) {
      throw StateError('Restore requires an empty note library.');
    }
    final lease = await acquireSyncLease(
      owner: 'portable-restore-${DateTime.now().microsecondsSinceEpoch}',
    );
    if (lease == null) throw StateError('Wait for the current sync to finish.');
    try {
      await _notesRoot.create(recursive: true);
      await for (final entity in source.list(recursive: true)) {
        if (entity is! File) continue;
        final relative = p
            .relative(entity.path, from: source.path)
            .replaceAll('\\', '/');
        final destination = _file(relative);
        await destination.parent.create(recursive: true);
        await entity.copy(destination.path);
      }
      await importExistingFilesIfNeeded();
      final notes = await notesForBackup();
      await _db.transaction(() async {
        for (final note in notes) {
          await (_db.update(
            _db.noteRows,
          )..where((row) => row.id.equals(note.id))).write(
            NoteRowsCompanion(
              isPinned: Value(pinnedByPath[note.path] ?? false),
              lastRemoteSha: const Value.absent(),
              isDirty: const Value(true),
            ),
          );
        }
        await for (final entity in _notesRoot.list(recursive: true)) {
          if (entity is! File) continue;
          final relative = p
              .relative(entity.path, from: _notesRoot.path)
              .replaceAll('\\', '/');
          if (!(relative.startsWith('attachments/') ||
              relative.startsWith('assets/'))) {
            continue;
          }
          final extension = p.extension(relative).toLowerCase();
          await _db
              .into(_db.attachments)
              .insertOnConflictUpdate(
                AttachmentsCompanion.insert(
                  path: relative,
                  mimeType: Value(_mimeFor(extension)),
                  lastRemoteSha: const Value.absent(),
                  isDirty: true,
                  updatedAt: DateTime.now().millisecondsSinceEpoch,
                ),
              );
        }
      });
      _scheduleSync();
    } finally {
      await releaseSyncLease(lease);
    }
  }

  Stream<List<Note>> search(String input) {
    final query = _db.select(_db.noteRows)
      ..where((row) => row.isPendingDeletion.equals(false));
    final term = input.trim();
    if (term.isNotEmpty) {
      final pattern = '%${term.replaceAll('%', '\\%').replaceAll('_', '\\_')}%';
      query.where((row) => row.title.like(pattern) | row.body.like(pattern));
      // A title hit is more likely to identify the intended note than a hit
      // somewhere in its content. Keep recently updated notes first within
      // each match group.
      query.orderBy([
        (row) => OrderingTerm.desc(row.title.like(pattern)),
        (row) => OrderingTerm.desc(row.updatedAt),
      ]);
    } else {
      query.orderBy([(row) => OrderingTerm.desc(row.updatedAt)]);
    }
    return query.watch().map((rows) => rows.map(_toNote).toList());
  }

  Stream<List<TodoItem>> watchTodos({bool includeCompleted = false}) {
    final query = _db.select(_db.todoEntries).join([
      innerJoin(
        _db.noteRows,
        _db.noteRows.id.equalsExp(_db.todoEntries.noteId),
      ),
    ])..where(_db.noteRows.isPendingDeletion.equals(false));
    if (!includeCompleted) {
      query.where(_db.todoEntries.isCompleted.equals(false));
    }
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
          .where((todo) => todo.text.trim().isNotEmpty)
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

  Future<List<Note>> dirtyNotes() async =>
      (await (_db.select(_db.noteRows)
                ..where((note) => note.isDirty.equals(true))
                ..orderBy([(note) => OrderingTerm.asc(note.updatedAt)]))
              .get())
          .map(_toNote)
          .toList();

  Future<void> applyRemote({
    required String path,
    required String sha,
    required String raw,
  }) async {
    final parsed = MarkdownContract.parse(raw);
    final id = MarkdownContract.identityFor(path, parsed.id);
    final previous = await get(id);
    final movedFromPath = previous?.path;
    final rebaseMovedNote = previous?.rawMarkdown == raw;
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
        summary: Value(parsed.summary),
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
      localMutation: false,
    );
    if (movedFromPath != null && movedFromPath != path) {
      await _rebaseLinksForMove(
        movedFromPath: movedFromPath,
        movedToPath: path,
        movedNoteId: id,
        rebaseMovedNote: rebaseMovedNote,
      );
    }
  }

  Future<SyncLease?> acquireSyncLease({
    required String owner,
    Duration duration = const Duration(minutes: 2),
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final expiresAt = now + duration.inMilliseconds;
    final acquired = await _db.transaction(() async {
      await _db.customStatement(
        'INSERT OR IGNORE INTO sync_leases (scope, owner, expiresAt) VALUES (?, ?, ?)',
        ['github', owner, 0],
      );
      return _db.customUpdate(
        '''
          UPDATE sync_leases SET owner = ?, expiresAt = ?
          WHERE scope = 'github' AND (expiresAt <= ? OR owner = ?)
        ''',
        variables: [
          Variable.withString(owner),
          Variable.withInt(expiresAt),
          Variable.withInt(now),
          Variable.withString(owner),
        ],
      );
    });
    return acquired == 1 ? SyncLease(owner: owner, expiresAt: expiresAt) : null;
  }

  Future<bool> renewSyncLease(
    SyncLease lease, {
    Duration duration = const Duration(minutes: 2),
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final expiresAt = now + duration.inMilliseconds;
    final updated = await _db.customUpdate(
      '''
        UPDATE sync_leases SET expiresAt = ?
        WHERE scope = 'github' AND owner = ? AND expiresAt > ?
      ''',
      variables: [
        Variable.withInt(expiresAt),
        Variable.withString(lease.owner),
        Variable.withInt(now),
      ],
    );
    lease.expiresAt = expiresAt;
    return updated == 1;
  }

  Future<void> releaseSyncLease(SyncLease lease) => _db.customUpdate(
    "UPDATE sync_leases SET expiresAt = 0 WHERE scope = 'github' AND owner = ?",
    variables: [Variable.withString(lease.owner)],
  );

  Future<void> markSynced(Note note, String sha) async {
    await acknowledgeNotesSynced({
      note.id: (revision: note.localRevision, sha: sha),
    });
  }

  /// Records a remote acknowledgement without losing an edit that was made
  /// while the HTTP request was in flight.  In that case the new remote SHA is
  /// still installed as the baseline, but the newer local revision remains
  /// dirty for the next commit.
  Future<void> acknowledgeNotesSynced(
    Map<String, ({int revision, String? sha})> acknowledgements,
  ) async {
    await _db.transaction(() async {
      for (final entry in acknowledgements.entries) {
        final current = await get(entry.key);
        if (current == null) continue;
        final acknowledgement = entry.value;
        if (current.localRevision == acknowledgement.revision &&
            current.isPendingDeletion) {
          await completeDeletion(current);
          continue;
        }
        final acknowledgedCurrentRevision =
            current.localRevision == acknowledgement.revision;
        await (_db.update(
          _db.noteRows,
        )..where((row) => row.id.equals(current.id))).write(
          NoteRowsCompanion(
            lastRemoteSha: Value(acknowledgement.sha),
            isDirty: Value(
              acknowledgedCurrentRevision ? false : current.isDirty,
            ),
            pendingRenameFromPath: Value(
              acknowledgedCurrentRevision
                  ? null
                  : current.pendingRenameFromPath,
            ),
            pendingRenameFromSha: Value(
              acknowledgedCurrentRevision ? null : current.pendingRenameFromSha,
            ),
          ),
        );
        if (acknowledgedCurrentRevision) {
          await (_db.delete(_db.syncOperations)..where(
                (operation) =>
                    operation.noteId.equals(current.id) &
                    operation.localRevision.isSmallerOrEqualValue(
                      acknowledgement.revision,
                    ),
              ))
              .go();
        }
      }
    });
  }

  Future<void> completeDeletion(Note note) async {
    await _db.transaction(() async {
      await (_db.delete(
        _db.todoEntries,
      )..where((row) => row.noteId.equals(note.id))).go();
      await (_db.delete(
        _db.noteRows,
      )..where((row) => row.id.equals(note.id))).go();
      await (_db.delete(
        _db.syncOperations,
      )..where((row) => row.noteId.equals(note.id))).go();
    });
  }

  /// Applies remote deletions without treating unsynced local notes as lost.
  /// Local edits to an already-synced note are retained as conflict copies.
  Future<void> reconcileRemoteRemovals(Set<String> remotePaths) async {
    final localNotes = (await _db.select(_db.noteRows).get()).map(_toNote);
    for (final note in localNotes) {
      final expectedRemotePath = note.isPendingDeletion
          ? note.pendingRenameFromPath ?? note.path
          : note.path;
      if (remotePaths.contains(expectedRemotePath)) continue;
      await _reconcileRemoteRemoval(note);
    }
  }

  /// Applies one known remote deletion without requiring a complete tree
  /// scan. This is used by GitHub's compare response for fast incremental
  /// pulls.
  Future<void> reconcileRemoteRemoval(String remotePath) async {
    final localNotes = (await _db.select(_db.noteRows).get()).map(_toNote);
    for (final note in localNotes) {
      final expectedRemotePath = note.isPendingDeletion
          ? note.pendingRenameFromPath ?? note.path
          : note.path;
      if (expectedRemotePath != remotePath) continue;
      await _reconcileRemoteRemoval(note);
    }
  }

  Future<void> _reconcileRemoteRemoval(Note note) async {
    // A pending deletion is already satisfied when its path is absent from
    // the remote snapshot. This includes local-only conflict copies, which
    // must not remain forever in the sync queue.
    if (note.isPendingDeletion) {
      await completeDeletion(note);
      return;
    }
    if (note.pendingRenameFromPath != null) return;

    // A note with no remote SHA has never been published, so its absence from
    // the remote tree is expected. Clean conflict copies, however, have a
    // remote SHA and should follow a remote deletion just like any other note.
    if (note.lastRemoteSha == null) return;
    if (note.isDirty) await preserveConflict(note);
    await _removeStoredNote(note);
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
    final conflictPath = await _availablePath(
      '${directory == '.' ? '' : '$directory/'}$base (conflict $suffix)$extension',
    );
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
      localMutation: false,
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

  Future<Note> createDaily(
    String path,
    String title, {
    String body = '',
  }) async {
    final id = '01${_uuid.v4().replaceAll('-', '').substring(0, 24)}';
    final normalizedTitle = title.trim().isEmpty ? 'Untitled' : title.trim();
    final normalizedBody = body.trim().isEmpty
        ? '# $normalizedTitle\n\n'
        : '# $normalizedTitle\n\n${body.trim()}\n';
    final raw = '${MarkdownContract.frontmatter(id)}$normalizedBody';
    final note = await _put(
      NoteRowsCompanion.insert(
        id: id,
        title: normalizedTitle,
        path: path,
        rawMarkdown: raw,
        body: normalizedBody,
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
    if (markdown.trim().isEmpty) {
      throw ArgumentError.value(
        markdown,
        'markdown',
        'A capture cannot be blank',
      );
    }
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
        summary: Value(parsed.summary),
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
    if (existing != null && existing.id != note.id) {
      throw StateError('A note already exists at $target.');
    }
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
        summary: Value(note.summary),
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
      operationKind: 'rename',
      operationFromPath: note.pendingRenameFromPath ?? note.path,
    );
    await _rebaseLinksForMove(
      movedFromPath: note.path,
      movedToPath: target,
      movedNoteId: note.id,
      rebaseMovedNote: true,
    );
    _scheduleSync();
    return (await get(updated.id))!;
  }

  /// Moves a note into the repository-root archive folder.
  ///
  /// Keeping only the filename makes the archive a single, predictable folder
  /// rather than mirroring each note's original directory structure.
  Future<Note> archive(Note note) =>
      rename(note, p.join('archive', p.basename(note.path)));

  /// Preserves relative Markdown links when a note changes path. The moved
  /// note's outbound links are rebased, while every other note updates only
  /// links that previously resolved to the moved note.
  Future<void> _rebaseLinksForMove({
    required String movedFromPath,
    required String movedToPath,
    required String movedNoteId,
    required bool rebaseMovedNote,
  }) async {
    final notes = (await _db.select(_db.noteRows).get()).map(_toNote);
    for (final note in notes) {
      if (note.isPendingDeletion ||
          (note.id == movedNoteId && !rebaseMovedNote)) {
        continue;
      }
      final isMovedNote = note.id == movedNoteId;
      final oldSourcePath = isMovedNote ? movedFromPath : note.path;
      final newSourcePath = note.path;
      final raw = MarkdownContract.rebaseNoteLinks(
        note.rawMarkdown,
        oldSourcePath: oldSourcePath,
        newSourcePath: newSourcePath,
        movedFromPath: movedFromPath,
        movedToPath: movedToPath,
      );
      final body = MarkdownContract.rebaseNoteLinks(
        note.body,
        oldSourcePath: oldSourcePath,
        newSourcePath: newSourcePath,
        movedFromPath: movedFromPath,
        movedToPath: movedToPath,
      );
      if (raw == note.rawMarkdown && body == note.body) continue;

      await _put(
        NoteRowsCompanion(
          id: Value(note.id),
          title: Value(note.title),
          path: Value(note.path),
          rawMarkdown: Value(raw),
          body: Value(body),
          aliases: Value(_encodeAliases(note.aliases)),
          summary: Value(note.summary),
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
    }
  }

  Future<void> delete(Note note) async {
    await _put(
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
      writeFile: false,
      operationKind: 'delete',
      operationFromPath: note.pendingRenameFromPath ?? note.path,
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
      body: TodoMarkdown.toggleGlobalAt(note.body, todo.taskIndex),
    );
  }

  /// Rebuilds the legacy task index once so existing local `- [ ]` checkboxes
  /// disappear from the global task list. Subsequent writes index only `+`.
  Future<void> migrateGlobalTaskIndex() async {
    const migrationId = 1;
    final state = await (_db.select(
      _db.todoIndexStates,
    )..where((row) => row.id.equals(migrationId))).getSingleOrNull();
    if (state?.isReady == true) return;

    await _db.transaction(() async {
      await _db.delete(_db.todoEntries).go();
      final notes = await _db.select(_db.noteRows).get();
      for (final note in notes) {
        await _indexGlobalTasks(note.id, note.body);
      }
      await _db
          .into(_db.todoIndexStates)
          .insertOnConflictUpdate(
            TodoIndexStatesCompanion.insert(
              id: Value(migrationId),
              isReady: const Value(true),
            ),
          );
    });
  }

  Future<Note> importImage(Note note, File source) async {
    if (!await source.exists()) {
      throw StateError('The selected image is no longer available.');
    }
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
        value.startsWith('file:')) {
      return null;
    }
    final base = value.startsWith('attachments/') || value.startsWith('assets/')
        ? ''
        : p.dirname(notePath);
    final resolved = p
        .normalize(p.join(base == '.' ? '' : base, value))
        .replaceAll('\\', '/');
    if (!(resolved.startsWith('attachments/') ||
            resolved.startsWith('assets/')) ||
        resolved.endsWith('.reflect.md')) {
      return null;
    }
    final file = _file(resolved);
    return await file.exists() ? file : null;
  }

  String attachmentReference(String notePath, String attachmentPath) {
    final parent = p.dirname(notePath);
    return p
        .relative(attachmentPath, from: parent == '.' ? '' : parent)
        .replaceAll('\\', '/');
  }

  Future<void> updateSummary(Note note, String summary) async {
    final plainSummary = MarkdownContract.plainText(summary);
    final raw = MarkdownContract.upsertSummary(
      note.rawMarkdown,
      note.id,
      plainSummary,
    );
    await _put(
      NoteRowsCompanion(
        id: Value(note.id),
        title: Value(note.title),
        path: Value(note.path),
        rawMarkdown: Value(raw),
        body: Value(note.body),
        aliases: Value(_encodeAliases(note.aliases)),
        summary: Value(plainSummary),
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
          summary: Value(parsed.summary),
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
        localMutation: false,
      );
    }
  }

  Future<Note> _put(
    NoteRowsCompanion note, {
    required bool writeFile,
    bool localMutation = true,
    String operationKind = 'upsert',
    String? operationFromPath,
  }) async {
    if (writeFile) await _write(note.path.value, note.rawMarkdown.value);
    await _db.transaction(() async {
      final previous = await (_db.select(
        _db.noteRows,
      )..where((row) => row.id.equals(note.id.value))).getSingleOrNull();
      final revision = localMutation
          ? (previous?.localRevision ?? 0) + 1
          : (previous?.localRevision ?? 0);
      final persisted = note.copyWith(localRevision: Value(revision));
      await _db.into(_db.noteRows).insertOnConflictUpdate(persisted);
      await _indexGlobalTasks(persisted.id.value, persisted.body.value);
      if (localMutation) {
        await _db
            .into(_db.syncOperations)
            .insert(
              SyncOperationsCompanion.insert(
                noteId: Value(persisted.id.value),
                kind: operationKind,
                path: persisted.path.value,
                fromPath: Value(operationFromPath),
                localRevision: revision,
                createdAt: DateTime.now().millisecondsSinceEpoch,
              ),
            );
      }
    });
    return (await get(note.id.value))!;
  }

  Future<String> _availablePath(String desiredPath) async {
    if (await findByPath(desiredPath) == null) return desiredPath;
    final directory = p.dirname(desiredPath);
    final extension = p.extension(desiredPath);
    final base = p.basenameWithoutExtension(desiredPath);
    for (var index = 2; ; index++) {
      final candidate =
          '${directory == '.' ? '' : '$directory/'}$base $index$extension';
      if (await findByPath(candidate) == null) return candidate;
    }
  }

  Future<void> _indexGlobalTasks(String noteId, String body) async {
    await (_db.delete(
      _db.todoEntries,
    )..where((row) => row.noteId.equals(noteId))).go();
    for (final task in TodoMarkdown.extract(body)) {
      await _db
          .into(_db.todoEntries)
          .insert(
            TodoEntriesCompanion.insert(
              noteId: noteId,
              taskIndex: task.index,
              taskText: task.text,
              isCompleted: task.completed,
            ),
          );
    }
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
    summary: row.summary == null
        ? null
        : MarkdownContract.plainText(row.summary!),
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
    localRevision: row.localRevision,
    updatedAt: DateTime.fromMillisecondsSinceEpoch(row.updatedAt),
  );
}

class SyncLease {
  SyncLease({required this.owner, required this.expiresAt});

  final String owner;
  int expiresAt;
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
