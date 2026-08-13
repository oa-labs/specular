import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io';
import 'package:appflowy_editor/appflowy_editor.dart';

import '../ai/ai_summary_service.dart';
import '../backup/backup_archive.dart';
import '../data/note_repository.dart';
import '../domain/markdown.dart';
import '../domain/note.dart';
import '../sync/github_sync.dart';
import '../sync/sync_scheduler.dart';
import '../voice/voice_service.dart';
import '../platform/document_bridge.dart';
import 'note_body_editor.dart';
import 'specular_app.dart';

enum NoteListSort { lastUpdated, alphabetical }

/// Returns the top-level note folder displayed in the Kotlin app's home list.
/// Files at the repository root, and internal asset folders, have no badge.
String? noteFolderLabel(Note note) {
  final separator = note.path.indexOf('/');
  if (separator <= 0) return null;
  final folder = note.path.substring(0, separator);
  if (folder.toLowerCase() == 'assets' ||
      folder.toLowerCase() == 'attachments') {
    return null;
  }
  return folder;
}

List<String> noteFolders(Iterable<Note> notes) {
  final folders = <String>{for (final note in notes) ?noteFolderLabel(note)};
  return folders.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
}

/// Folders offered while creating a regular note. Daily and attachment
/// directories are managed by their own flows and cannot be selected here.
List<String> creationFolders(Iterable<Note> notes) => noteFolders(
  notes,
).where((folder) => folder.toLowerCase() != 'daily').toList();

/// A previous release stored the normalized note body as a fallback summary.
/// Treat those values as missing so they are not shown and the AI can replace
/// them with an actual generated summary.
bool hasUsableSummary(Note note) {
  final summary = note.summary?.trim();
  return summary?.isNotEmpty == true &&
      summary != MarkdownContract.plainText(note.body);
}

List<Note> sortAndFilterNotes(
  Iterable<Note> notes, {
  required NoteListSort sort,
  required Set<String> deselectedFolders,
}) {
  final visible = notes
      .where((note) => !deselectedFolders.contains(noteFolderLabel(note)))
      .toList();
  int compareText(Note a, Note b) {
    final byTitle = a.title.toLowerCase().compareTo(b.title.toLowerCase());
    return byTitle != 0 ? byTitle : a.path.compareTo(b.path);
  }

  visible.sort((a, b) {
    if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
    if (sort == NoteListSort.alphabetical) return compareText(a, b);
    final byUpdated = b.updatedAt.compareTo(a.updatedAt);
    return byUpdated != 0 ? byUpdated : compareText(a, b);
  });
  return visible;
}

/// A pull that found the same remote head deserves an explicit confirmation:
/// the note list does not otherwise visibly change.
String syncRefreshMessage(SyncResult result) => result.noRemoteChanges
    ? 'Checked GitHub — no new changes found.'
    : result.message;

class NoteListScreen extends ConsumerStatefulWidget {
  const NoteListScreen({super.key});

  @override
  ConsumerState<NoteListScreen> createState() => _NoteListScreenState();
}

class _NoteListScreenState extends ConsumerState<NoteListScreen> {
  static const _deselectedFoldersKey = 'deselected_folders';
  var _sort = NoteListSort.lastUpdated;
  var _deselectedFolders = <String>{};
  var _loadedPreferences = false;
  var _createExpanded = false;
  var _openingToday = false;
  var _onboardingComplete = false;
  var _backupPromptDismissed = false;
  BackupStatus? _backupStatus;
  final _summaryJobs = <String>{};

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final value = await ref
        .read(secureStorageProvider)
        .read(key: _deselectedFoldersKey);
    if (!mounted) return;
    setState(() {
      _deselectedFolders =
          value?.split('\u001f').where((it) => it.isNotEmpty).toSet() ?? {};
      _loadedPreferences = true;
    });
    _loadFirstRunState();
    _refreshBackupStatus();
  }

  Future<void> _loadFirstRunState() async {
    final storage = ref.read(secureStorageProvider);
    final values = await Future.wait([
      storage.read(key: onboardingCompletedStorageKey),
      storage.read(key: backupPromptDismissedStorageKey),
    ]);
    if (!mounted) return;
    setState(() {
      _onboardingComplete = values[0] == 'true';
      _backupPromptDismissed = values[1] == 'true';
    });
  }

  Future<void> _refreshBackupStatus() async {
    final status = await readBackupStatus(
      ref.read(secureStorageProvider),
      ref.read(noteRepositoryProvider),
    );
    if (!mounted) return;
    setState(() => _backupStatus = status);
  }

  Future<void> _completeOnboarding({String? destination}) async {
    await ref
        .read(secureStorageProvider)
        .write(key: onboardingCompletedStorageKey, value: 'true');
    if (!mounted) return;
    setState(() => _onboardingComplete = true);
    context.push(destination ?? '/editor/new');
  }

  Future<void> _dismissBackupPrompt() async {
    await ref
        .read(secureStorageProvider)
        .write(key: backupPromptDismissedStorageKey, value: 'true');
    if (mounted) setState(() => _backupPromptDismissed = true);
  }

  Future<void> _saveDeselectedFolders() => ref
      .read(secureStorageProvider)
      .write(
        key: _deselectedFoldersKey,
        value: _deselectedFolders.join('\u001f'),
      );

  void _toggleFolder(String folder) {
    setState(() {
      if (!_deselectedFolders.add(folder)) _deselectedFolders.remove(folder);
    });
    _saveDeselectedFolders();
  }

  void _showAllFolders() {
    setState(() => _deselectedFolders = {});
    _saveDeselectedFolders();
  }

  Future<void> _openToday() async {
    if (_openingToday) return;
    setState(() => _openingToday = true);
    try {
      final date = DateTime.now().toIso8601String().substring(0, 10);
      final note = await ref
          .read(noteRepositoryProvider)
          .findByPath('daily/$date.md');
      if (!mounted) return;
      if (note != null) {
        context.push('/editor/${Uri.encodeComponent(note.id)}');
      } else {
        // A missing daily note remains a draft until the editor is saved.
        context.push('/editor/new?daily=$date');
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to open today\'s note: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _openingToday = false);
    }
  }

  Future<void> _refresh() async {
    final result = await ref.read(syncControllerProvider).sync();
    if (!mounted) return;

    // The database watch normally updates the list after a pull. Invalidating
    // also makes a completed refresh visibly re-check the stream when the
    // remote contained no changes.
    ref.invalidate(notesProvider);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(syncRefreshMessage(result))));
    unawaited(_refreshBackupStatus());
  }

  Future<void> _generateMissingSummaries(List<Note> notes) async {
    // Onboarding and repository imports must establish their remote baseline
    // before derived AI metadata is allowed to alter Markdown. Otherwise a
    // freshly imported note can look like a competing local edit and produce
    // a needless conflict copy.
    final initialSyncCompleted =
        await ref
            .read(secureStorageProvider)
            .read(key: initialSyncCompletedStorageKey) ==
        'true';
    if (!initialSyncCompleted) return;
    final generator = ref.read(aiSummaryServiceProvider);
    if (!await generator.isConfigured()) return;
    for (final note in notes) {
      if (note.isPendingDeletion ||
          note.isDirty ||
          hasUsableSummary(note) ||
          !_summaryJobs.add(note.id)) {
        continue;
      }
      unawaited(_generateSummary(note, generator));
    }
  }

  Future<void> _generateSummary(Note note, AiSummaryService generator) async {
    try {
      // Always use the current version so an edit or pull that happened after
      // this job was queued cannot have its summary written to stale content.
      final current = await ref.read(noteRepositoryProvider).get(note.id);
      if (current == null ||
          current.isPendingDeletion ||
          hasUsableSummary(current)) {
        return;
      }
      final summary = await generator.generate(current.body);
      final latest = await ref.read(noteRepositoryProvider).get(note.id);
      if (latest == null ||
          latest.isPendingDeletion ||
          hasUsableSummary(latest)) {
        return;
      }
      await ref.read(noteRepositoryProvider).updateSummary(latest, summary);
      ref.invalidate(notesProvider);
    } catch (_) {
      // A missing provider configuration or a transient API error should not
      // interrupt the note list. The note remains eligible for a later retry.
    } finally {
      _summaryJobs.remove(note.id);
    }
  }

  void _showViewOptions(List<Note> notes) {
    final folders = noteFolders(notes);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * .85,
          ),
          child: StatefulBuilder(
            builder: (context, setSheetState) => SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'View options',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Sort and choose the folders shown on your home screen.',
                    ),
                    const SizedBox(height: 16),
                    Text('Sort', style: Theme.of(context).textTheme.titleSmall),
                    RadioGroup<NoteListSort>(
                      groupValue: _sort,
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => _sort = value);
                        setSheetState(() {});
                      },
                      child: Column(
                        children: const [
                          RadioListTile<NoteListSort>(
                            value: NoteListSort.lastUpdated,
                            contentPadding: EdgeInsets.zero,
                            title: Text('Last updated'),
                          ),
                          RadioListTile<NoteListSort>(
                            value: NoteListSort.alphabetical,
                            contentPadding: EdgeInsets.zero,
                            title: Text('Title, A–Z'),
                          ),
                        ],
                      ),
                    ),
                    if (folders.isNotEmpty) ...[
                      const Divider(height: 24),
                      Row(
                        children: [
                          const Icon(Icons.filter_list),
                          const SizedBox(width: 12),
                          Text(
                            'Folders',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const Spacer(),
                          if (_deselectedFolders.isNotEmpty)
                            TextButton(
                              onPressed: () {
                                _showAllFolders();
                                setSheetState(() {});
                              },
                              child: const Text('Show all'),
                            ),
                        ],
                      ),
                      for (final folder in folders)
                        CheckboxListTile(
                          value: !_deselectedFolders.contains(folder),
                          contentPadding: EdgeInsets.zero,
                          title: Text(folder),
                          onChanged: (_) {
                            _toggleFolder(folder);
                            setSheetState(() {});
                          },
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final notesState = ref.watch(notesProvider);
    final allNotes = notesState.asData?.value ?? const <Note>[];
    if (notesState.hasValue) unawaited(_generateMissingSummaries(allNotes));
    final notes = sortAndFilterNotes(
      allNotes,
      sort: _sort,
      deselectedFolders: _deselectedFolders,
    );
    return Scaffold(
      appBar: AppBar(
        title: SpecularWordmark(
          isSyncing: ref.watch(syncControllerProvider).state.isSyncing,
        ),
        actions: [
          IconButton(
            tooltip: 'View to-dos',
            onPressed: () => context.push('/todos'),
            icon: const Icon(Icons.checklist),
          ),
          IconButton(
            tooltip: 'Open today\'s note',
            onPressed: _openingToday ? null : _openToday,
            icon: _openingToday
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.calendar_today),
          ),
          IconButton(
            tooltip: 'Search notes',
            onPressed: () => context.push('/search'),
            icon: const Icon(Icons.search),
          ),
          PopupMenuButton<_HomeAction>(
            tooltip: 'More actions',
            onSelected: (action) {
              switch (action) {
                case _HomeAction.viewOptions:
                  _showViewOptions(allNotes);
                  break;
                case _HomeAction.settings:
                  context.push('/settings');
                  break;
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: _HomeAction.viewOptions,
                child: Row(
                  children: const [
                    Icon(Icons.tune),
                    SizedBox(width: 12),
                    Text('View options'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: _HomeAction.settings,
                child: Row(
                  children: const [
                    Icon(Icons.settings),
                    SizedBox(width: 12),
                    Text('Settings'),
                  ],
                ),
              ),
            ],
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Badge(
                isLabelVisible: _deselectedFolders.isNotEmpty,
                child: const Icon(Icons.more_vert),
              ),
            ),
          ),
        ],
      ),
      body: !_loadedPreferences || notesState.isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: notesState.when(
                data: (_) {
                  if (allNotes.isEmpty && !_onboardingComplete) {
                    return _FirstRunWelcome(
                      onStart: () => _completeOnboarding(),
                      onCreateBackup: () => _completeOnboarding(
                        destination: '/settings?setup=guided',
                      ),
                      onConnectExisting: () => _completeOnboarding(
                        destination: '/settings?setup=existing',
                      ),
                    );
                  }
                  if (notes.isEmpty) {
                    return _RefreshableMessage(
                      allNotes.isEmpty
                          ? 'No notes yet. Tap the calendar to start today\'s note.'
                          : 'No notes in selected folders. Open View options to change them.',
                    );
                  }
                  return ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(bottom: 88),
                    itemCount:
                        notes.length +
                        ((_backupStatus?.kind == BackupStatusKind.localOnly &&
                                !_backupPromptDismissed)
                            ? 1
                            : 0),
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, index) {
                      if (index == 0 &&
                          _backupStatus?.kind == BackupStatusKind.localOnly &&
                          !_backupPromptDismissed) {
                        return _BackupStatusCard(
                          status: _backupStatus!,
                          onOpenSettings: () => context.push('/settings'),
                          onDismiss: _dismissBackupPrompt,
                        );
                      }
                      final noteIndex =
                          _backupStatus?.kind == BackupStatusKind.localOnly &&
                              !_backupPromptDismissed
                          ? index - 1
                          : index;
                      final note = notes[noteIndex];
                      return _NoteTile(key: ValueKey(note.id), note: note);
                    },
                  );
                },
                error: (error, _) =>
                    _RefreshableMessage('Unable to load notes: $error'),
                loading: () => const Center(child: CircularProgressIndicator()),
              ),
            ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (_createExpanded) ...[
            FloatingActionButton.extended(
              heroTag: 'new-note',
              onPressed: () {
                setState(() => _createExpanded = false);
                context.push('/editor/new');
              },
              icon: const Icon(Icons.add),
              label: const Text('New note'),
            ),
            const SizedBox(height: 12),
            FloatingActionButton.extended(
              heroTag: 'new-todo',
              onPressed: () {
                setState(() => _createExpanded = false);
                context.push('/editor/todo');
              },
              icon: const Icon(Icons.checklist),
              label: const Text('New to-do'),
            ),
            const SizedBox(height: 12),
            FloatingActionButton.extended(
              heroTag: 'voice-capture',
              onPressed: () {
                setState(() => _createExpanded = false);
                context.push('/voice');
              },
              icon: const Icon(Icons.mic),
              label: const Text('Voice capture'),
            ),
            const SizedBox(height: 12),
          ],
          FloatingActionButton(
            heroTag: 'create-menu',
            tooltip: _createExpanded ? 'Close create menu' : 'Create new item',
            onPressed: () => setState(() => _createExpanded = !_createExpanded),
            child: Icon(_createExpanded ? Icons.close : Icons.add),
          ),
        ],
      ),
    );
  }
}

enum _HomeAction { viewOptions, settings }

class _RefreshableMessage extends StatelessWidget {
  const _RefreshableMessage(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(
          height: constraints.maxHeight,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(message, textAlign: TextAlign.center),
            ),
          ),
        ),
      ],
    ),
  );
}

class _FirstRunWelcome extends StatelessWidget {
  const _FirstRunWelcome({
    required this.onStart,
    required this.onCreateBackup,
    required this.onConnectExisting,
  });

  final VoidCallback onStart;
  final VoidCallback onCreateBackup;
  final VoidCallback onConnectExisting;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Write first. Back up when you’re ready.',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            const Text(
              'Specular saves notes on this device and works offline. A GitHub '
              'backup is optional, but protects notes when you change or lose a device.',
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onStart,
              icon: const Icon(Icons.edit_note),
              label: const Text('Start on this device'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onCreateBackup,
              icon: const Icon(Icons.cloud_upload_outlined),
              label: const Text('Create a private GitHub backup'),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: onConnectExisting,
              icon: const Icon(Icons.folder_open),
              label: const Text('Connect an existing repository'),
            ),
          ],
        ),
      ),
    ),
  );
}

class _BackupStatusCard extends StatelessWidget {
  const _BackupStatusCard({
    required this.status,
    required this.onOpenSettings,
    required this.onDismiss,
  });

  final BackupStatus status;
  final VoidCallback onOpenSettings;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.secondaryContainer,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(Icons.cloud_off_outlined),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Your notes are not backed up'),
                SizedBox(height: 2),
                Text('Set up GitHub backup any time from Settings.'),
              ],
            ),
          ),
          PopupMenuButton<_BackupCardAction>(
            onSelected: (action) {
              if (action == _BackupCardAction.settings) onOpenSettings();
              if (action == _BackupCardAction.dismiss) onDismiss();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: _BackupCardAction.settings,
                child: Text('Set up backup'),
              ),
              PopupMenuItem(
                value: _BackupCardAction.dismiss,
                child: Text('Dismiss'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

enum _BackupCardAction { settings, dismiss }

class _NoteTile extends ConsumerStatefulWidget {
  const _NoteTile({super.key, required this.note});
  final Note note;

  @override
  ConsumerState<_NoteTile> createState() => _NoteTileState();
}

class _NoteTileState extends ConsumerState<_NoteTile>
    with SingleTickerProviderStateMixin {
  static const _holdDuration = Duration(milliseconds: 500);

  late final AnimationController _holdProgress;
  late bool _isPinned;

  @override
  void initState() {
    super.initState();
    _isPinned = widget.note.isPinned;
    _holdProgress = AnimationController(vsync: this, duration: _holdDuration);
  }

  @override
  void didUpdateWidget(covariant _NoteTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.note.id != widget.note.id ||
        oldWidget.note.isPinned != widget.note.isPinned) {
      _isPinned = widget.note.isPinned;
    }
  }

  @override
  void dispose() {
    _holdProgress.dispose();
    super.dispose();
  }

  void _beginHold(TapDownDetails _) {
    _holdProgress.forward(from: 0);
  }

  void _cancelHold() {
    _holdProgress.reverse();
  }

  Future<void> _togglePinned() async {
    final pinned = !_isPinned;
    _holdProgress.forward();
    setState(() => _isPinned = pinned);
    HapticFeedback.mediumImpact();
    try {
      await ref.read(noteRepositoryProvider).setPinned(widget.note, pinned);
      ref.invalidate(notesProvider);
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(content: Text(pinned ? 'Note pinned' : 'Note unpinned')),
          );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isPinned = !pinned);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('Could not update pin')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final note = widget.note;
    final folder = noteFolderLabel(note);
    final summary = hasUsableSummary(note) ? note.summary! : '';
    final hasMetadata = folder != null || note.isConflict;
    final theme = Theme.of(context);
    return Semantics(
      label:
          '${note.title.isEmpty ? 'Untitled' : note.title}, '
          '${_isPinned ? 'pinned' : 'not pinned'}',
      hint: 'Press and hold to ${_isPinned ? 'unpin' : 'pin'}',
      child: AnimatedBuilder(
        animation: _holdProgress,
        builder: (context, child) => Transform.scale(
          scale: 1 - (_holdProgress.value * .015),
          child: Stack(
            children: [
              child!,
              if (_holdProgress.value > 0)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: _holdProgress.value,
                      child: Container(
                        height: 2,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        child: InkWell(
          onTap: () => context.push('/note/${Uri.encodeComponent(note.id)}'),
          onTapDown: _beginHold,
          onTapCancel: _cancelHold,
          onTapUp: (_) => _cancelHold(),
          onLongPress: _togglePinned,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (_isPinned)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Tooltip(
                          message: 'Pinned',
                          child: Icon(
                            Icons.push_pin,
                            size: 16,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                    Expanded(
                      child: Text(
                        note.title.isEmpty ? 'Untitled' : note.title,
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
                if (summary.isNotEmpty || hasMetadata)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (summary.isNotEmpty)
                          Expanded(
                            child: Text(
                              summary,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        if (summary.isNotEmpty && hasMetadata)
                          const SizedBox(width: 8),
                        if (note.isConflict)
                          const Icon(
                            Icons.warning_amber_rounded,
                            color: Colors.orange,
                          ),
                        if (note.isConflict && folder != null)
                          const SizedBox(width: 8),
                        if (folder != null) _FolderBadge(label: folder),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FolderBadge extends StatelessWidget {
  const _FolderBadge({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 2),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primary.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      label,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
  );
}

class NoteDetailScreen extends ConsumerWidget {
  const NoteDetailScreen({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Keep this preview in sync after a checkbox mutates its source note.
    ref.watch(notesProvider);
    return FutureBuilder<Note?>(
      future: ref.read(noteRepositoryProvider).get(id),
      builder: (context, snapshot) {
        final note = snapshot.data;
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (note == null) {
          return const Scaffold(body: Center(child: Text('Note not found')));
        }
        return Scaffold(
          appBar: AppBar(
            actions: [
              IconButton(
                tooltip: 'Generate AI summary',
                onPressed: () => _generateSummary(context, ref, note),
                icon: const Icon(Icons.auto_awesome),
              ),
              TextButton.icon(
                key: const ValueKey('edit-note'),
                onPressed: () =>
                    context.push('/editor/${Uri.encodeComponent(note.id)}'),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Edit'),
              ),
              PopupMenuButton<_NoteAction>(
                onSelected: (action) {
                  switch (action) {
                    case _NoteAction.pin:
                      _setPinned(ref, note, !note.isPinned);
                      break;
                    case _NoteAction.rename:
                      _rename(context, ref, note);
                      break;
                    case _NoteAction.archive:
                      _archive(context, ref, note);
                      break;
                    case _NoteAction.delete:
                      _delete(context, ref, note);
                      break;
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: _NoteAction.pin,
                    child: Text(note.isPinned ? 'Unpin' : 'Pin'),
                  ),
                  const PopupMenuItem(
                    value: _NoteAction.rename,
                    child: Text('Rename'),
                  ),
                  if (!note.path.startsWith('archive/'))
                    const PopupMenuItem(
                      value: _NoteAction.archive,
                      child: Text('Archive'),
                    ),
                  const PopupMenuItem(
                    value: _NoteAction.delete,
                    child: Text('Delete'),
                  ),
                ],
              ),
            ],
          ),
          body: _NotePreviewBody(note: note),
        );
      },
    );
  }

  static Future<void> _generateSummary(
    BuildContext context,
    WidgetRef ref,
    Note note,
  ) async {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Generating summary…')));
    try {
      final summary = await ref
          .read(aiSummaryServiceProvider)
          .generate(note.body);
      await ref.read(noteRepositoryProvider).updateSummary(note, summary);
      ref.invalidate(notesProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Summary: $summary')));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  static Future<void> _setPinned(
    WidgetRef ref,
    Note note,
    bool isPinned,
  ) async {
    await ref.read(noteRepositoryProvider).setPinned(note, isPinned);
    ref.invalidate(notesProvider);
  }

  static Future<void> _rename(
    BuildContext context,
    WidgetRef ref,
    Note note,
  ) async {
    final controller = TextEditingController(text: note.path);
    final requested = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rename note'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Repository-relative path',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (requested == null) return;
    try {
      final renamed = await ref
          .read(noteRepositoryProvider)
          .rename(note, requested);
      if (context.mounted) {
        context.go('/note/${Uri.encodeComponent(renamed.id)}');
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  static Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    Note note,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete note?'),
        content: Text(
          '“${note.title}” will be deleted locally and on its next GitHub sync.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(noteRepositoryProvider).delete(note);
    if (!context.mounted) return;
    if (GoRouter.of(context).canPop()) {
      context.pop();
    } else {
      context.go('/');
    }
  }

  static Future<void> _archive(
    BuildContext context,
    WidgetRef ref,
    Note note,
  ) async {
    try {
      final archived = await ref.read(noteRepositoryProvider).archive(note);
      if (context.mounted) {
        context.go('/note/${Uri.encodeComponent(archived.id)}');
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }
}

class _NotePreviewBody extends ConsumerWidget {
  const _NotePreviewBody({required this.note});
  final Note note;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    var taskIndex = 0;
    return Column(
      children: [
        Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Summary',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const Spacer(),
                  Semantics(
                    label: 'Read-only preview. Use Edit to change this note.',
                    child: Tooltip(
                      message:
                          'Read-only preview. Use Edit to change this note.',
                      child: Icon(
                        Icons.visibility_outlined,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                hasUsableSummary(note) ? note.summary! : 'No summary available',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontStyle: FontStyle.italic,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Markdown(
            data: NoteBodyEditorCodec.normalizeTaskListSpacing(note.body),
            padding: const EdgeInsets.all(16),
            // Task text and its interactive checkbox must share the same top edge,
            // including when the task spans multiple lines.
            listItemCrossAxisAlignment:
                MarkdownListItemCrossAxisAlignment.start,
            onTapLink: (_, href, _) => _openLink(context, ref, href),
            imageBuilder: (uri, title, alt) =>
                _AttachmentImage(notePath: note.path, uri: uri),
            checkboxBuilder: (checked) {
              final index = taskIndex++;
              return Checkbox(
                value: checked,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                onChanged: (_) => _toggleTodo(ref, note, index),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _toggleTodo(WidgetRef ref, Note displayed, int taskIndex) async {
    final repository = ref.read(noteRepositoryProvider);
    final current = await repository.get(displayed.id);
    if (current == null) return;
    await repository.save(
      current,
      title: current.title,
      body: TodoMarkdown.toggleCheckboxAt(current.body, taskIndex),
    );
    ref.invalidate(notesProvider);
  }

  Future<void> _openLink(
    BuildContext context,
    WidgetRef ref,
    String? href,
  ) async {
    final targetPath = MarkdownContract.resolveNoteLink(note.path, href ?? '');
    if (targetPath != null) {
      final target = await ref
          .read(noteRepositoryProvider)
          .findByPath(targetPath);
      if (target != null && context.mounted) {
        context.push('/note/${Uri.encodeComponent(target.id)}');
      } else if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Linked note is not available locally: $targetPath'),
          ),
        );
      }
      return;
    }

    final uri = Uri.tryParse(href ?? '');
    if (uri == null || !uri.hasScheme) return;
    if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Unable to open link.')));
    }
  }
}

enum _NoteAction { pin, rename, archive, delete }

class _AttachmentImage extends ConsumerStatefulWidget {
  const _AttachmentImage({required this.notePath, required this.uri});
  final String notePath;
  final Uri uri;

  @override
  ConsumerState<_AttachmentImage> createState() => _AttachmentImageState();
}

class _AttachmentImageState extends ConsumerState<_AttachmentImage> {
  late Future<File?> _file;

  @override
  void initState() {
    super.initState();
    _file = _resolveFile();
  }

  @override
  void didUpdateWidget(covariant _AttachmentImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.notePath != widget.notePath || oldWidget.uri != widget.uri) {
      _file = _resolveFile();
    }
  }

  Future<File?> _resolveFile() => ref
      .read(noteRepositoryProvider)
      .resolveAttachment(widget.notePath, widget.uri.path);

  @override
  Widget build(BuildContext context) => FutureBuilder<File?>(
    future: _file,
    builder: (context, snapshot) {
      final file = snapshot.data;
      if (file == null) {
        return const Padding(
          padding: EdgeInsets.all(8),
          child: Icon(Icons.broken_image_outlined),
        );
      }
      return Semantics(
        button: true,
        label: 'View image full screen',
        child: GestureDetector(
          key: const ValueKey('open-image-preview'),
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.of(context).push<void>(
            MaterialPageRoute(
              builder: (_) => _FullscreenImageViewer(file: file),
              fullscreenDialog: true,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              child: Image.file(
                file,
                errorBuilder: (_, _, _) =>
                    const Icon(Icons.broken_image_outlined),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _FullscreenImageViewer extends StatelessWidget {
  const _FullscreenImageViewer({required this.file});
  final File file;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      title: const Text('Image'),
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
    ),
    body: Center(
      child: InteractiveViewer(
        minScale: 0.5,
        maxScale: 5,
        child: Image.file(
          file,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => const Icon(
            Icons.broken_image_outlined,
            color: Colors.white,
            size: 48,
          ),
        ),
      ),
    ),
  );
}

class EditorScreen extends ConsumerStatefulWidget {
  const EditorScreen({
    super.key,
    this.id,
    this.newTodo = false,
    this.dailyDate,
    this.startVoice = false,
  });
  final String? id;
  final bool newTodo;
  final String? dailyDate;
  final bool startVoice;

  @override
  ConsumerState<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends ConsumerState<EditorScreen> {
  static const _inboxFolderOption = '__specular_inbox__';
  static final _globalTaskMobileToolbarItem = MobileToolbarItem.action(
    itemIconBuilder: (context, _, _) =>
        Icon(Icons.task_alt, color: MobileToolbarTheme.of(context).iconColor),
    actionHandler: (_, editorState) async {
      final selection = editorState.selection;
      if (selection == null) return;
      final node = editorState.getNodeAtPath(selection.start.path);
      if (node == null) return;
      final isGlobalTask =
          node.type == TodoListBlockKeys.type &&
          node.attributes[NoteBodyEditorCodec.globalTaskAttribute] == true;
      await editorState.formatNode(
        selection,
        (node) => node.copyWith(
          type: isGlobalTask ? ParagraphBlockKeys.type : TodoListBlockKeys.type,
          attributes: {
            TodoListBlockKeys.checked: false,
            ParagraphBlockKeys.delta: (node.delta ?? Delta()).toJson(),
            if (!isGlobalTask) NoteBodyEditorCodec.globalTaskAttribute: true,
          },
        ),
      );
    },
  );
  static final _localCheckboxMobileToolbarItem = MobileToolbarItem.action(
    itemIconBuilder: (context, _, _) => Icon(
      Icons.check_box_outline_blank,
      color: MobileToolbarTheme.of(context).iconColor,
    ),
    actionHandler: (_, editorState) async {
      final selection = editorState.selection;
      if (selection == null) return;
      final node = editorState.getNodeAtPath(selection.start.path);
      if (node == null) return;
      final isLocalCheckbox =
          node.type == TodoListBlockKeys.type &&
          node.attributes[NoteBodyEditorCodec.globalTaskAttribute] != true;
      await editorState.formatNode(
        selection,
        (node) => node.copyWith(
          type: isLocalCheckbox
              ? ParagraphBlockKeys.type
              : TodoListBlockKeys.type,
          attributes: {
            TodoListBlockKeys.checked: false,
            ParagraphBlockKeys.delta: (node.delta ?? Delta()).toJson(),
          },
        ),
      );
    },
  );

  final _title = TextEditingController();
  Note? _note;
  EditorState? _editorState;
  final _stagedImages = <StagedImage>[];
  final _editorFocus = FocusNode(debugLabel: 'note editor');
  var _loading = true;
  var _saving = false;
  var _voiceRecording = false;
  var _willRewriteUnsupportedMarkdown = false;
  String? _selectedFolder;
  final _images = ImagePicker();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.id != null) {
      _note = await ref.read(noteRepositoryProvider).get(widget.id!);
      _title.text = _note?.title ?? '';
      if (_note != null) {
        _willRewriteUnsupportedMarkdown =
            MarkdownCompatibility.requiresRewriteWarning(_note!.body);
      }
    } else if (widget.newTodo) {
      _title.text = 'New to-do';
    } else if (widget.dailyDate != null) {
      _title.text = widget.dailyDate!;
    }
    _editorState = await NoteBodyEditorCodec.load(
      _note,
      ref.read(noteRepositoryProvider),
    );
    if (widget.newTodo) {
      _editorState = EditorState(
        document: NoteBodyEditorCodec.documentFromMarkdown('+ [ ] '),
      );
    }
    if (mounted) {
      setState(() => _loading = false);
      if (widget.startVoice) unawaited(_recordVoice());
    }
  }

  Future<void> _recordVoice() async {
    if (_voiceRecording || _loading) return;
    if (_note == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Save this note before recording into it.'),
        ),
      );
      return;
    }
    setState(() => _voiceRecording = true);
    try {
      final repo = ref.read(noteRepositoryProvider);
      await repo.commitStagedImages(_stagedImages);
      _stagedImages.clear();
      _note = await repo.save(
        _note!,
        title: _title.text,
        body: NoteBodyEditorCodec.export(_editorState!),
      );
      if (!mounted) return;
      final transcript = await context.push<String>(
        '/voice?note=${Uri.encodeQueryComponent(_note!.id)}',
      );
      if (transcript == null || transcript.trim().isEmpty || !mounted) return;
      await _editorState!.insertTextAtCurrentSelection(
        '\n\n${transcript.trim()}',
      );
      _note = await repo.save(
        _note!,
        title: _title.text,
        body: NoteBodyEditorCodec.export(_editorState!),
      );
      await ref.read(voiceServiceProvider).acknowledgeSaved();
      ref.invalidate(notesProvider);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to record voice note: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _voiceRecording = false);
    }
  }

  Future<void> _save() async {
    final editorState = _editorState;
    if (editorState == null) return;
    if (_willRewriteUnsupportedMarkdown &&
        !await _confirmUnsupportedMarkdownRewrite()) {
      return;
    }
    setState(() => _saving = true);
    try {
      final repo = ref.read(noteRepositoryProvider);
      final body = NoteBodyEditorCodec.export(editorState);
      // The editor only enables images for persisted notes, so their stable
      // repository-relative paths are available before they are inserted.
      await repo.commitStagedImages(_stagedImages);
      _stagedImages.clear();
      final saved = widget.newTodo
          ? await repo.appendToToday(body)
          : widget.dailyDate != null
          ? await repo.createDaily(
              'daily/${widget.dailyDate}.md',
              _title.text,
              body: body,
            )
          : _note == null
          ? await repo.create(
              title: _title.text,
              body: body,
              folder: _selectedFolder,
            )
          : await repo.save(_note!, title: _title.text, body: body);
      if (mounted) context.go('/note/${Uri.encodeComponent(saved.id)}');
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Unable to save note: $error')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _confirmUnsupportedMarkdownRewrite() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rewrite unsupported Markdown?'),
        content: const Text(
          'This note contains Markdown that the rich editor cannot preserve '
          'exactly. Saving will rewrite it using the supported Markdown set.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Save anyway'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _addImage(ImageSource source) async {
    if (_note == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Save the note before adding an image.')),
      );
      return;
    }
    final image = await _images.pickImage(source: source, imageQuality: 90);
    if (image == null) return;
    try {
      final repository = ref.read(noteRepositoryProvider);
      final staged = await repository.stageImage(File(image.path));
      await NoteBodyEditorCodec.insertStagedImage(
        _editorState!,
        staged,
        repository.attachmentReference(_note!.path, staged.attachmentPath),
      );
      if (mounted) {
        setState(() => _stagedImages.add(staged));
        // Returning from the native picker leaves focus on the toolbar. Move
        // it to the editable paragraph that follows the inserted image.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _editorFocus.requestFocus();
        });
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Unable to add image: $error')));
      }
    }
  }

  Future<void> _insertWikiLink() async {
    final selected = await showModalBottomSheet<Note>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _WikiLinkPicker(excludingId: _note?.id),
    );
    if (selected == null || _editorState == null) return;
    await _editorState!.insertTextAtCurrentSelection('[[${selected.title}]]');
  }

  @override
  void dispose() {
    unawaited(
      ref.read(noteRepositoryProvider).discardStagedImages(_stagedImages),
    );
    _editorState?.dispose();
    _editorFocus.dispose();
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final folders = creationFolders(
      ref.watch(notesProvider).asData?.value ?? const <Note>[],
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.newTodo
              ? 'New to-do'
              : _note == null
              ? 'New note'
              : 'Edit note',
        ),
        actions: [
          IconButton(
            tooltip: 'Insert wiki link',
            onPressed: _saving || _loading ? null : _insertWikiLink,
            icon: const Icon(Icons.link),
          ),
          IconButton(
            onPressed: _saving ? null : () => _addImage(ImageSource.camera),
            icon: const Icon(Icons.photo_camera),
          ),
          IconButton(
            onPressed: _saving ? null : () => _addImage(ImageSource.gallery),
            icon: const Icon(Icons.photo_library),
          ),
          IconButton(
            tooltip: 'Record into note',
            onPressed: _saving || _voiceRecording ? null : _recordVoice,
            icon: _voiceRecording
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.mic),
          ),
          TextButton.icon(
            key: const ValueKey('save-note'),
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.done),
            label: const Text('Done'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.edit_outlined,
                          color: Theme.of(
                            context,
                          ).colorScheme.onPrimaryContainer,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Editing — changes are saved when you tap Done.',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onPrimaryContainer,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _title,
                    decoration: const InputDecoration(labelText: 'Title'),
                  ),
                  if (_note == null && !widget.newTodo)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: PopupMenuButton<String>(
                        tooltip: 'Choose note folder',
                        initialValue: _selectedFolder ?? _inboxFolderOption,
                        onSelected: (folder) => setState(
                          () => _selectedFolder = folder == _inboxFolderOption
                              ? null
                              : folder,
                        ),
                        itemBuilder: (_) => [
                          const PopupMenuItem<String>(
                            value: _inboxFolderOption,
                            child: Text('Inbox'),
                          ),
                          for (final folder in folders)
                            PopupMenuItem<String>(
                              value: folder,
                              child: Text(folder),
                            ),
                        ],
                        child: Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.folder_outlined),
                              const SizedBox(width: 8),
                              Text('Save to: ${_selectedFolder ?? 'Inbox'}'),
                              const Icon(Icons.arrow_drop_down),
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (_willRewriteUnsupportedMarkdown) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Saving this note will rewrite unsupported Markdown.',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Expanded(
                    // MobileToolbar reserves a keyboard-height spacer inside
                    // this flex layout. On Android that repeatedly relayouts
                    // the editor while IME insets animate, and can starve the
                    // UI thread on a sufficiently large document. The V2
                    // toolbar is AppFlowy's supported mobile integration: it
                    // renders in an overlay and only reserves its fixed height
                    // in the editor layout.
                    child: MobileToolbarV2(
                      editorState: _editorState!,
                      toolbarItems: [
                        headingMobileToolbarItem,
                        textDecorationMobileToolbarItemV2,
                        codeMobileToolbarItem,
                        linkMobileToolbarItem,
                        listMobileToolbarItem,
                        _globalTaskMobileToolbarItem,
                        // A note-local checkbox is deliberately distinct from
                        // the global `+ [ ]` task action above.
                        _localCheckboxMobileToolbarItem,
                        quoteMobileToolbarItem,
                        dividerMobileToolbarItem,
                      ],
                      child: AppFlowyEditor(
                        editorState: _editorState!,
                        focusNode: _editorFocus,
                        // Do not create an initial selection in block zero:
                        // AppFlowy's mobile auto-scroll listener would then
                        // pull a manually scrolled long note back to the top.
                        autoFocus: false,
                        // Keep the scroll service because it maps touch
                        // coordinates to virtualized blocks for selection. A
                        // zero edge stops its buggy automatic edge-scrolling
                        // loop; regular finger scrolling remains unchanged.
                        autoScrollEdgeOffset: 0,
                        editorStyle: EditorStyle.mobile(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          cursorColor: Theme.of(context).colorScheme.primary,
                          textStyleConfiguration: TextStyleConfiguration(
                            text: Theme.of(context).textTheme.bodyLarge!,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

/// Searches the local note index as the user types, then inserts the selected
/// title using Reflect's portable `[[wikilink]]` syntax.
class _WikiLinkPicker extends ConsumerStatefulWidget {
  const _WikiLinkPicker({this.excludingId});

  final String? excludingId;

  @override
  ConsumerState<_WikiLinkPicker> createState() => _WikiLinkPickerState();
}

class _WikiLinkPickerState extends ConsumerState<_WikiLinkPicker> {
  var _query = '';

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .65,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
              child: TextField(
                autofocus: true,
                onChanged: (value) => setState(() => _query = value),
                decoration: const InputDecoration(
                  labelText: 'Link to note',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
            ),
            Expanded(
              child: StreamBuilder<List<Note>>(
                stream: ref.read(noteRepositoryProvider).search(_query),
                builder: (_, snapshot) {
                  final notes = (snapshot.data ?? const <Note>[])
                      .where((note) => note.id != widget.excludingId)
                      .take(30)
                      .toList();
                  if (notes.isEmpty) {
                    return const Center(child: Text('No matching notes'));
                  }
                  return ListView.builder(
                    itemCount: notes.length,
                    itemBuilder: (_, index) {
                      final note = notes[index];
                      return ListTile(
                        leading: const Icon(Icons.description_outlined),
                        title: Text(note.title),
                        subtitle: Text(note.path),
                        onTap: () => Navigator.pop(context, note),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});
  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  var _query = '';
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: TextField(
        autofocus: true,
        onChanged: (value) => setState(() => _query = value),
        decoration: const InputDecoration(hintText: 'Search notes'),
      ),
    ),
    body: StreamBuilder<List<Note>>(
      stream: ref.read(noteRepositoryProvider).search(_query),
      builder: (_, snapshot) => ListView(
        children: [
          for (final note in snapshot.data ?? const <Note>[])
            _NoteTile(note: note),
        ],
      ),
    ),
  );
}

class TodoScreen extends ConsumerWidget {
  const TodoScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => DefaultTabController(
    length: TodoFilter.values.length,
    child: Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SpecularWordmark(
              isSyncing: ref.watch(syncControllerProvider).state.isSyncing,
            ),
            const Padding(
              padding: EdgeInsets.only(left: 10),
              child: Text('To-dos'),
            ),
          ],
        ),
        bottom: const TabBar(
          tabs: [
            Tab(text: 'Open'),
            Tab(text: 'Done'),
            Tab(text: 'All'),
          ],
        ),
      ),
      body: const TabBarView(
        children: [
          _TodoList(filter: TodoFilter.open),
          _TodoList(filter: TodoFilter.done),
          _TodoList(filter: TodoFilter.all),
        ],
      ),
    ),
  );
}

class _TodoList extends ConsumerStatefulWidget {
  const _TodoList({required this.filter});

  final TodoFilter filter;

  @override
  ConsumerState<_TodoList> createState() => _TodoListState();
}

/// Keeps note groups from jumping when an update changes the repository's
/// default ordering. New tasks join their existing note group, while tasks
/// from a newly seen note are added in repository order.
List<TodoItem> preserveTodoOrder(
  List<TodoItem> todos,
  List<TodoItem> previousOrder,
) {
  final todosByNote = <String, List<TodoItem>>{};
  for (final todo in todos) {
    todosByNote.putIfAbsent(todo.noteId, () => []).add(todo);
  }

  final orderedNoteIds = <String>{};
  final orderedTodos = <TodoItem>[];
  for (final todo in previousOrder) {
    if (orderedNoteIds.add(todo.noteId)) {
      orderedTodos.addAll(todosByNote[todo.noteId] ?? const []);
    }
  }
  for (final todo in todos) {
    if (orderedNoteIds.add(todo.noteId)) {
      orderedTodos.addAll(todosByNote[todo.noteId]!);
    }
  }
  return orderedTodos;
}

List<List<TodoItem>> groupTodosByNote(Iterable<TodoItem> todos) {
  final groups = <String, List<TodoItem>>{};
  for (final todo in todos) {
    groups.putIfAbsent(todo.noteId, () => []).add(todo);
  }
  return groups.values.toList(growable: false);
}

class _TodoListState extends ConsumerState<_TodoList> {
  var _previousOrder = <TodoItem>[];

  Future<void> _refresh() async {
    final result = await ref.read(syncControllerProvider).sync();
    if (!mounted) return;

    ref.invalidate(todosProvider(widget.filter));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(syncRefreshMessage(result))));
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: _refresh,
    child: ref
        .watch(todosProvider(widget.filter))
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) =>
              _RefreshableMessage('Unable to load to-dos: $error'),
          data: (todos) {
            final orderedTodos = preserveTodoOrder(todos, _previousOrder);
            _previousOrder = orderedTodos;
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                for (final todosForNote in groupTodosByNote(orderedTodos))
                  _TodoNoteGroup(
                    key: ValueKey(todosForNote.first.noteId),
                    todos: todosForNote,
                  ),
              ],
            );
          },
        ),
  );
}

class _TodoNoteGroup extends StatelessWidget {
  const _TodoNoteGroup({super.key, required this.todos});

  final List<TodoItem> todos;

  @override
  Widget build(BuildContext context) {
    final note = todos.first;
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () =>
                context.push('/note/${Uri.encodeComponent(note.noteId)}'),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Text(
                note.noteTitle,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
          ),
          for (final todo in todos)
            _TodoRow(key: ValueKey((todo.noteId, todo.taskIndex)), todo: todo),
        ],
      ),
    );
  }
}

class _TodoRow extends ConsumerWidget {
  const _TodoRow({super.key, required this.todo});
  final TodoItem todo;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          // Align the checkbox glyph with the first line, rather than centering
          // it beside a task that wraps over several lines.
          padding: const EdgeInsets.only(top: 1, right: 8),
          child: Checkbox(
            value: todo.isCompleted,
            semanticLabel: 'Mark ${todo.text} complete',
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
            onChanged: (_) => ref.read(noteRepositoryProvider).toggleTodo(todo),
          ),
        ),
        Expanded(
          child: InkWell(
            onTap: () =>
                context.push('/note/${Uri.encodeComponent(todo.noteId)}'),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MarkdownBody(
                    data: todo.text,
                    styleSheet: MarkdownStyleSheet.fromTheme(
                      Theme.of(context),
                    ).copyWith(p: Theme.of(context).textTheme.bodyLarge),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class VoiceCaptureScreen extends ConsumerStatefulWidget {
  const VoiceCaptureScreen({super.key, this.noteId});
  final String? noteId;
  @override
  ConsumerState<VoiceCaptureScreen> createState() => _VoiceCaptureScreenState();
}

class _VoiceCaptureScreenState extends ConsumerState<VoiceCaptureScreen> {
  final _transcript = TextEditingController();
  var _recording = false;
  var _busy = false;
  var _asTodo = false;
  String? _error;
  String _liveTranscript = '';
  String _status = '';
  StreamSubscription? _updates;
  VoiceSession? _recoverableSession;

  @override
  void initState() {
    super.initState();
    unawaited(_findRecovery());
  }

  Future<void> _findRecovery() async {
    final sessions = await ref.read(voiceServiceProvider).recoverableSessions();
    if (mounted && sessions.isNotEmpty) {
      setState(() => _recoverableSession = sessions.first);
    }
  }

  Future<void> _retryRecovery() async {
    final session = _recoverableSession;
    if (session == null) return;
    setState(() => _busy = true);
    try {
      final transcript = await ref.read(voiceServiceProvider).retry(session);
      if (mounted) {
        setState(() {
          _transcript.text = transcript;
          _recoverableSession = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _start() async {
    try {
      final service = ref.read(voiceServiceProvider);
      _updates ??= service.updates.listen((update) {
        if (!mounted) return;
        setState(() {
          if (update.text.isNotEmpty) _liveTranscript += update.text;
          if (update.status != null) _status = update.status!;
        });
      });
      await service.start(noteId: widget.noteId);
      if (mounted) setState(() => _recording = true);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  Future<void> _stop() async {
    setState(() => _busy = true);
    try {
      final transcript = await ref
          .read(voiceServiceProvider)
          .stopAndTranscribe();
      if (mounted) {
        setState(() {
          _transcript.text = transcript;
          _recording = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _recording = false;
          _error = '$error';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (_transcript.text.trim().isEmpty) return;
    if (widget.noteId != null) {
      context.pop(_transcript.text.trim());
      return;
    }
    setState(() => _busy = true);
    try {
      final note = await ref
          .read(noteRepositoryProvider)
          .appendToToday(
            _asTodo ? '- [ ] ${_transcript.text.trim()}' : _transcript.text,
          );
      await ref.read(voiceServiceProvider).acknowledgeSaved();
      if (mounted) context.go('/note/${Uri.encodeComponent(note.id)}');
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _transcript.dispose();
    unawaited(_updates?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Voice capture')),
    body: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Audio is saved locally first. Live text may pause when offline and will recover from the saved recording.',
          ),
          if (_status.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_status),
            ),
          if (_recoverableSession != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _retryRecovery,
                icon: const Icon(Icons.restore),
                label: const Text('Recover saved voice recording'),
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: 20),
          if (_transcript.text.isNotEmpty)
            Expanded(
              child: TextField(
                controller: _transcript,
                maxLines: null,
                expands: true,
                decoration: const InputDecoration(
                  labelText: 'Transcript',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          if (_transcript.text.isEmpty)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: SingleChildScrollView(
                  child: Text(
                    _liveTranscript.isEmpty
                        ? (_recording ? 'Listening…' : '')
                        : _liveTranscript,
                  ),
                ),
              ),
            ),
          SwitchListTile(
            value: _asTodo,
            onChanged: _busy
                ? null
                : (value) => setState(() => _asTodo = value),
            title: const Text('Save as to-do'),
          ),
          if (_transcript.text.isNotEmpty)
            FilledButton(
              onPressed: _busy ? null : _save,
              child: Text(
                _asTodo ? 'Add to-do to today' : 'Add thought to today',
              ),
            )
          else
            FilledButton.icon(
              onPressed: _busy ? null : (_recording ? _stop : _start),
              icon: Icon(_recording ? Icons.stop : Icons.mic),
              label: Text(
                _busy
                    ? 'Transcribing…'
                    : (_recording ? 'Stop and transcribe' : 'Start recording'),
              ),
            ),
        ],
      ),
    ),
  );
}

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  static const _defaultSummaryModel = 'deepseek/deepseek-v4-flash-0731';
  static const _defaultVoiceModel = 'gpt-live-transcribe';
  static const _defaultVoiceFileModel = 'gpt-transcribe';
  static const _defaultVoiceCleanupModel = 'gpt-5-mini';

  final _token = TextEditingController();
  final _owner = TextEditingController();
  final _repo = TextEditingController();
  final _aiUrl = TextEditingController();
  final _aiKey = TextEditingController();
  final _aiModel = TextEditingController();
  final _voiceModel = TextEditingController();
  final _voiceEndpoint = TextEditingController();
  final _voiceKey = TextEditingController();
  final _voiceOpenAiKey = TextEditingController();
  final _voiceFileModel = TextEditingController();
  final _voiceCleanupModel = TextEditingController();
  var _voiceProvider = 'OPENROUTER';
  var _usePreviewKey = true;
  var _loaded = false;
  var _saving = false;
  var _loadingRepositories = false;
  var _selectingRepository = false;
  var _syncIntervalMinutes = SyncScheduler.defaultIntervalMinutes;
  var _syncDiagnosticsEnabled = false;
  var _configuredOwner = '';
  var _configuredRepo = '';
  String? _repositoryError;
  BackupStatus? _backupStatus;

  bool get _isChangingRepository =>
      _configuredOwner.isNotEmpty &&
      (_owner.text.trim() != _configuredOwner ||
          _repo.text.trim() != _configuredRepo);

  Future<void> _load() async {
    if (_loaded) return;
    _loaded = true;
    final storage = ref.read(secureStorageProvider);
    _token.text = await storage.read(key: 'github_token') ?? '';
    _owner.text = await storage.read(key: 'repo_owner') ?? '';
    _repo.text = await storage.read(key: 'repo_name') ?? '';
    _configuredOwner = _owner.text.trim();
    _configuredRepo = _repo.text.trim();
    _syncIntervalMinutes = await SyncScheduler.intervalFromStorage(storage);
    _syncDiagnosticsEnabled = await SyncDiagnostics.isEnabled(storage);
    _aiUrl.text = await storage.read(key: 'ai_provider_url') ?? '';
    _aiKey.text = await storage.read(key: 'ai_provider_api_key') ?? '';
    _aiModel.text =
        await storage.read(key: 'ai_provider_model_id') ?? _defaultSummaryModel;
    _voiceProvider = await storage.read(key: 'voice_provider') ?? 'OPENROUTER';
    _voiceModel.text =
        await storage.read(key: 'voice_model_id') ?? _defaultVoiceModel;
    _voiceEndpoint.text = await storage.read(key: 'voice_endpoint') ?? '';
    _voiceKey.text = await storage.read(key: 'voice_api_key') ?? '';
    _voiceOpenAiKey.text =
        await storage.read(key: 'voice_openai_api_key') ??
        (_voiceProvider == 'OPENAI' ? _voiceKey.text : '');
    _voiceFileModel.text =
        await storage.read(key: 'voice_file_model') ?? _defaultVoiceFileModel;
    _voiceCleanupModel.text =
        await storage.read(key: 'voice_cleanup_model') ??
        _defaultVoiceCleanupModel;
    _usePreviewKey =
        await storage.read(key: 'voice_use_preview_key') != 'false';
    _backupStatus = await readBackupStatus(
      storage,
      ref.read(noteRepositoryProvider),
    );
    if (mounted) setState(() {});
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      if (_isChangingRepository) {
        throw StateError(
          'Use “Switch repository” to clear the local mirror before changing remotes.',
        );
      }
      await _persistSettings();
      final sync = await ref.read(syncControllerProvider).sync();
      if (mounted) {
        _backupStatus = await readBackupStatus(
          ref.read(secureStorageProvider),
          ref.read(noteRepositoryProvider),
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Settings saved. ${sync.message}')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _persistSettings() async {
    final storage = ref.read(secureStorageProvider);
    await storage.write(key: 'github_token', value: _token.text.trim());
    await storage.write(key: 'repo_owner', value: _owner.text.trim());
    await storage.write(key: 'repo_name', value: _repo.text.trim());
    await storage.write(key: 'ai_provider_url', value: _aiUrl.text.trim());
    await storage.write(key: 'ai_provider_api_key', value: _aiKey.text.trim());
    await storage.write(
      key: 'ai_provider_model_id',
      value: _aiModel.text.trim(),
    );
    await storage.write(key: 'voice_provider', value: _voiceProvider);
    await storage.write(key: 'voice_model_id', value: _voiceModel.text.trim());
    await storage.write(
      key: 'voice_endpoint',
      value: _voiceEndpoint.text.trim(),
    );
    await storage.write(key: 'voice_api_key', value: _voiceKey.text.trim());
    await storage.write(
      key: 'voice_openai_api_key',
      value: _voiceOpenAiKey.text.trim(),
    );
    await storage.write(
      key: 'voice_file_model',
      value: _voiceFileModel.text.trim(),
    );
    await storage.write(
      key: 'voice_cleanup_model',
      value: _voiceCleanupModel.text.trim(),
    );
    await storage.write(
      key: 'voice_use_preview_key',
      value: _usePreviewKey.toString(),
    );
    await SyncScheduler.setInterval(storage, _syncIntervalMinutes);
    _configuredOwner = _owner.text.trim();
    _configuredRepo = _repo.text.trim();
  }

  Future<void> _disconnectGitHub() async {
    if (_saving) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Disconnect GitHub?'),
        content: const Text(
          'Notes will stay on this device. Specular will stop syncing and will not change the GitHub repository.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    try {
      final storage = ref.read(secureStorageProvider);
      await Future.wait([
        storage.delete(key: 'github_token'),
        storage.delete(key: 'repo_owner'),
        storage.delete(key: 'repo_name'),
        storage.delete(key: initialSyncCompletedStorageKey),
        storage.delete(key: lastSuccessfulGitHubSyncStorageKey),
      ]);
      _token.clear();
      _owner.clear();
      _repo.clear();
      _configuredOwner = '';
      _configuredRepo = '';
      _backupStatus = const BackupStatus(kind: BackupStatusKind.localOnly);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('GitHub disconnected. Local notes were kept.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _exportPortableBackup() async {
    if (_saving) return;
    setState(() => _saving = true);
    final bridge = DocumentBridge();
    File? temporary;
    try {
      final directory = await getTemporaryDirectory();
      temporary = File(
        '${directory.path}/specular-backup-${DateTime.now().millisecondsSinceEpoch}.zip',
      );
      await BackupArchiveService(
        ref.read(noteRepositoryProvider),
      ).exportTo(temporary);
      final uri = await bridge.createBackupDocument();
      if (uri == null) return;
      await bridge.writeDocument(uri: uri, sourcePath: temporary.path);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Portable backup exported.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to export backup: $error')),
        );
      }
    } finally {
      if (temporary != null && await temporary.exists()) {
        await temporary.delete();
      }
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _restorePortableBackup() async {
    if (_saving) return;
    final repository = ref.read(noteRepositoryProvider);
    if (await repository.hasLocalNotes() || _configuredOwner.isNotEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Restore requires an empty library with GitHub disconnected.',
            ),
          ),
        );
      }
      return;
    }
    if (await repository.isGitHubSyncActive()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Wait for the current sync to finish before restoring.',
            ),
          ),
        );
      }
      return;
    }
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Restore a portable backup?'),
        content: const Text(
          'Choose a Specular backup archive. Restored notes remain local until you set up backup again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Choose backup'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    Directory? temporary;
    try {
      final uri = await DocumentBridge().openBackupDocument();
      if (uri == null) return;
      final root = await getTemporaryDirectory();
      temporary = await Directory(
        '${root.path}/specular-restore-${DateTime.now().millisecondsSinceEpoch}',
      ).create();
      final archive = File('${temporary.path}/backup.zip');
      await DocumentBridge().readDocument(
        uri: uri,
        destinationPath: archive.path,
      );
      final service = BackupArchiveService(repository);
      final prepared = await service.prepareRestore(
        archive,
        Directory('${temporary.path}/staging'),
      );
      await service.restore(prepared);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Backup restored. Set up backup when you are ready.'),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to restore backup: $error')),
        );
      }
    } finally {
      if (temporary != null && await temporary.exists()) {
        await temporary.delete(recursive: true);
      }
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _confirmCacheClear({required bool switching}) async {
    final unsynced = await ref
        .read(noteRepositoryProvider)
        .hasPendingSyncChanges();
    if (!mounted) return false;
    final action = switching ? 'switch repositories' : 'clear the local cache';
    return (await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(
              switching ? 'Switch repository?' : 'Clear local cache?',
            ),
            content: Text(
              'This will remove all local notes, attachments, and search data. '
              'Your GitHub repository will not be changed.'
              '${unsynced ? ' Unsynced local edits will be permanently lost.' : ''}',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton.tonal(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(action),
              ),
            ],
          ),
        )) ??
        false;
  }

  Future<void> _clearLocalCache({required bool switching}) async {
    if (_saving) return;
    if (!await _confirmCacheClear(switching: switching)) return;
    setState(() => _saving = true);
    try {
      final storage = ref.read(secureStorageProvider);
      await ref.read(noteRepositoryProvider).clearLocalCache();
      await storage.delete(key: initialSyncCompletedStorageKey);
      if (switching) await _persistSettings();
      final sync = await ref.read(syncControllerProvider).sync();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              switching
                  ? 'Repository switched. ${sync.message}'
                  : 'Local cache cleared. ${sync.message}',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to update cache: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _switchRepository() async {
    if (_saving || !_isChangingRepository) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(syncEngineProvider)
          .validateRepositoryCoordinates(
            _token.text,
            owner: _owner.text,
            repo: _repo.text,
          );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Repository cannot be selected: $error')),
        );
      }
      return;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    await _clearLocalCache(switching: true);
  }

  Future<void> _setDarkMode(bool value) async {
    final mode = value ? ThemeMode.dark : ThemeMode.light;
    ref.read(themeModeControllerProvider).setThemeMode(mode);
    await ref
        .read(secureStorageProvider)
        .write(key: themeModeStorageKey, value: themeModeStorageValue(mode));
  }

  Future<void> _setSyncDiagnostics(bool value) async {
    setState(() => _syncDiagnosticsEnabled = value);
    try {
      await ref.read(syncControllerProvider).setDiagnosticsEnabled(value);
    } catch (_) {
      if (mounted) setState(() => _syncDiagnosticsEnabled = !value);
    }
  }

  Future<void> _showSyncLog() async {
    final entries = await SyncDiagnostics.read(ref.read(secureStorageProvider));
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * .7,
          child: Column(
            children: [
              const ListTile(title: Text('GitHub sync log')),
              Expanded(
                child: entries.isEmpty
                    ? const Center(
                        child: Text('No sync activity recorded yet.'),
                      )
                    : ListView.separated(
                        itemCount: entries.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (_, index) {
                          final entry = entries[entries.length - 1 - index];
                          return ListTile(
                            dense: true,
                            title: Text(entry.message),
                            subtitle: Text(_syncLogTimestamp(entry.timestamp)),
                          );
                        },
                      ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () async {
                    await SyncDiagnostics.clear(
                      ref.read(secureStorageProvider),
                    );
                    if (sheetContext.mounted) Navigator.pop(sheetContext);
                  },
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Clear log'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _runFullGitHubSync() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final result = await ref
          .read(syncControllerProvider)
          .sync(forceFullRemoteScan: true);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(result.message)));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _chooseRepository() async {
    if (_loadingRepositories || _selectingRepository) return;
    final token = _token.text.trim();
    if (token.isEmpty) {
      setState(() {
        _repositoryError = 'Enter a GitHub personal access token first.';
      });
      return;
    }
    setState(() {
      _loadingRepositories = true;
      _repositoryError = null;
    });
    try {
      final repositories = await ref
          .read(syncEngineProvider)
          .listRepositories(token);
      if (!mounted) return;
      if (repositories.isEmpty) {
        setState(() {
          _repositoryError =
              'No accessible repositories were found for this token.';
        });
        return;
      }
      final selected = await showModalBottomSheet<GitHubRepository>(
        context: context,
        isScrollControlled: true,
        builder: (sheetContext) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(sheetContext).height * .8,
            ),
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(24, 20, 24, 8),
                  child: Text('Choose a GitHub repository'),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(24, 0, 24, 12),
                  child: Text(
                    'Choose a repository for your Markdown notes. Empty repositories are ready for your first sync.',
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: repositories.length,
                    itemBuilder: (_, index) {
                      final repository = repositories[index];
                      return ListTile(
                        title: Text(repository.fullName),
                        subtitle: Text(
                          '${repository.isPrivate ? 'Private' : 'Public'} · ${repository.defaultBranch}',
                        ),
                        onTap: () => Navigator.pop(sheetContext, repository),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      if (selected != null) await _selectRepository(token, selected);
    } catch (error) {
      if (mounted) setState(() => _repositoryError = '$error');
    } finally {
      if (mounted) setState(() => _loadingRepositories = false);
    }
  }

  Future<void> _selectRepository(
    String token,
    GitHubRepository repository,
  ) async {
    setState(() {
      _selectingRepository = true;
      _repositoryError = null;
    });
    try {
      await ref.read(syncEngineProvider).validateRepository(token, repository);
      if (!mounted) return;
      setState(() {
        _owner.text = repository.owner;
        _repo.text = repository.name;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${repository.fullName} is ready to connect.')),
      );
    } catch (error) {
      if (mounted) setState(() => _repositoryError = '$error');
    } finally {
      if (mounted) setState(() => _selectingRepository = false);
    }
  }

  Future<String?> _askForRepositoryName() async {
    final controller = TextEditingController(text: 'specular-notes');
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Name your private backup'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Repository name',
            helperText: 'Only you can see this repository unless you share it.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Create backup'),
          ),
        ],
      ),
    );
    controller.dispose();
    return value?.isEmpty == true ? null : value;
  }

  Future<void> _createPrivateBackup() async {
    if (_saving) return;
    final auth = ref.read(gitHubAuthorizationProvider);
    if (!auth.isConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'GitHub sign-in is not enabled in this build. Use a personal access token below.',
          ),
        ),
      );
      return;
    }
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Connect GitHub backup'),
        content: const Text(
          'GitHub will ask you to authorize Specular to create and sync a private repository. '
          'This uses GitHub’s repository access permission. You can disconnect at any time.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Continue to GitHub'),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    setState(() => _saving = true);
    try {
      final token = await auth.authorize();
      if (!mounted) return;
      setState(() => _saving = false);
      final name = await _askForRepositoryName();
      if (name == null || !mounted) return;
      setState(() => _saving = true);
      final repository = await ref
          .read(syncEngineProvider)
          .createPrivateRepository(token, name: name);
      _token.text = token;
      _owner.text = repository.owner;
      _repo.text = repository.name;
      await _persistSettings();
      final result = await ref.read(syncControllerProvider).sync();
      _backupStatus = await readBackupStatus(
        ref.read(secureStorageProvider),
        ref.read(noteRepositoryProvider),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Private backup created. ${result.message}')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to create GitHub backup: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _token.dispose();
    _owner.dispose();
    _repo.dispose();
    _aiUrl.dispose();
    _aiKey.dispose();
    _aiModel.dispose();
    _voiceModel.dispose();
    _voiceEndpoint.dispose();
    _voiceKey.dispose();
    _voiceOpenAiKey.dispose();
    _voiceFileModel.dispose();
    _voiceCleanupModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _load();
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            SwitchListTile(
              value:
                  ref.watch(themeModeControllerProvider).themeMode ==
                  ThemeMode.dark,
              onChanged: _setDarkMode,
              secondary: const Icon(Icons.dark_mode),
              title: const Text('Dark mode'),
              subtitle: const Text('Turn off for light mode.'),
            ),
            const Divider(),
            if (_backupStatus != null)
              ListTile(
                leading: Icon(switch (_backupStatus!.kind) {
                  BackupStatusKind.localOnly => Icons.cloud_off_outlined,
                  BackupStatusKind.pending => Icons.cloud_upload_outlined,
                  BackupStatusKind.backedUp => Icons.cloud_done_outlined,
                }),
                title: Text(switch (_backupStatus!.kind) {
                  BackupStatusKind.localOnly => 'Not backed up',
                  BackupStatusKind.pending => 'Backup pending',
                  BackupStatusKind.backedUp => 'Backed up',
                }),
                subtitle: Text(
                  _backupStatus!.kind == BackupStatusKind.localOnly
                      ? 'Notes are currently stored only on this device.'
                      : _backupStatus!.repository ?? '',
                ),
              ),
            if (_configuredOwner.isEmpty)
              FilledButton.icon(
                onPressed: _saving ? null : _createPrivateBackup,
                icon: const Icon(Icons.cloud_upload_outlined),
                label: const Text('Create a private GitHub backup'),
              ),
            if (_configuredOwner.isNotEmpty)
              OutlinedButton.icon(
                onPressed: _saving ? null : _disconnectGitHub,
                icon: const Icon(Icons.link_off),
                label: const Text('Disconnect GitHub'),
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _saving ? null : _exportPortableBackup,
              icon: const Icon(Icons.save_alt_outlined),
              label: const Text('Export portable backup'),
            ),
            if (_configuredOwner.isEmpty)
              OutlinedButton.icon(
                onPressed: _saving ? null : _restorePortableBackup,
                icon: const Icon(Icons.restore),
                label: const Text('Restore portable backup'),
              ),
            const SizedBox(height: 12),
            Text(
              'Advanced: use a personal access token',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _token,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'GitHub personal access token',
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _loadingRepositories || _selectingRepository
                  ? null
                  : _chooseRepository,
              icon: _loadingRepositories || _selectingRepository
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.folder_open),
              label: Text(
                _selectingRepository
                    ? 'Validating repository…'
                    : (_loadingRepositories
                          ? 'Loading repositories…'
                          : 'Choose repository'),
              ),
            ),
            if (_repositoryError != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _repositoryError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            TextField(
              controller: _owner,
              decoration: const InputDecoration(labelText: 'Repository owner'),
            ),
            TextField(
              controller: _repo,
              decoration: const InputDecoration(labelText: 'Repository name'),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              key: ValueKey(_syncIntervalMinutes),
              initialValue: _syncIntervalMinutes,
              decoration: const InputDecoration(labelText: 'Background sync'),
              items: [
                for (final minutes in SyncScheduler.intervalChoices)
                  DropdownMenuItem(
                    value: minutes,
                    child: Text(_syncIntervalLabel(minutes)),
                  ),
              ],
              onChanged: _saving
                  ? null
                  : (minutes) {
                      if (minutes != null) {
                        setState(() => _syncIntervalMinutes = minutes);
                      }
                    },
            ),
            ExpansionTile(
              leading: const Icon(Icons.bug_report_outlined),
              title: const Text('Sync diagnostics'),
              subtitle: const Text(
                'Show detailed sync stages and keep a troubleshooting log.',
              ),
              children: [
                SwitchListTile(
                  value: _syncDiagnosticsEnabled,
                  onChanged: _setSyncDiagnostics,
                  title: const Text('Show detailed sync stages'),
                ),
                ListTile(
                  leading: const Icon(Icons.receipt_long_outlined),
                  title: const Text('View sync log'),
                  subtitle: const Text(
                    'The most recent 30 phase and error messages.',
                  ),
                  onTap: _showSyncLog,
                ),
                ListTile(
                  leading: const Icon(Icons.manage_search_outlined),
                  title: const Text('Full GitHub sync'),
                  subtitle: const Text(
                    'Check every remote note and apply remote deletions.',
                  ),
                  enabled: !_saving,
                  onTap: _saving ? null : _runFullGitHubSync,
                ),
              ],
            ),
            if (_isChangingRepository) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _saving ? null : _switchRepository,
                icon: const Icon(Icons.swap_horiz),
                label: const Text('Switch repository'),
              ),
              const Text(
                'Switching clears this device’s local mirror before importing '
                'the selected repository.',
              ),
            ],
            if (_configuredOwner.isNotEmpty) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _saving || _isChangingRepository
                    ? null
                    : () => _clearLocalCache(switching: false),
                icon: const Icon(Icons.delete_sweep_outlined),
                label: const Text('Clear local sync cache'),
              ),
            ],
            ExpansionTile(
              title: const Text('AI summary provider'),
              children: [
                TextField(
                  controller: _aiUrl,
                  decoration: const InputDecoration(
                    labelText: 'OpenAI-compatible endpoint',
                  ),
                ),
                TextField(
                  controller: _aiKey,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'API key'),
                ),
                TextField(
                  controller: _aiModel,
                  decoration: const InputDecoration(labelText: 'Model'),
                ),
              ],
            ),
            ExpansionTile(
              title: const Text('Voice transcription and cleanup'),
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: Text(
                    'Live transcription, recovery uploads, and light cleanup use your OpenAI API key directly.',
                  ),
                ),
                TextField(
                  controller: _voiceOpenAiKey,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'OpenAI voice API key',
                  ),
                ),
                TextField(
                  controller: _voiceModel,
                  decoration: const InputDecoration(
                    labelText: 'Live transcription model',
                  ),
                ),
                TextField(
                  controller: _voiceFileModel,
                  decoration: const InputDecoration(
                    labelText: 'Recovery transcription model',
                  ),
                ),
                TextField(
                  controller: _voiceCleanupModel,
                  decoration: const InputDecoration(labelText: 'Cleanup model'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cloud_sync),
              label: Text(_saving ? 'Saving and syncing…' : 'Save and sync'),
            ),
          ],
        ),
      ),
    );
  }
}

String _syncIntervalLabel(int minutes) {
  if (minutes < 60) return 'Every $minutes minutes';
  final hours = minutes ~/ 60;
  return hours == 1 ? 'Every hour' : 'Every $hours hours';
}

String _syncLogTimestamp(DateTime timestamp) {
  final local = timestamp.toLocal();
  String twoDigits(int value) => value.toString().padLeft(2, '0');
  return '${local.year}-${twoDigits(local.month)}-${twoDigits(local.day)} '
      '${twoDigits(local.hour)}:${twoDigits(local.minute)}:${twoDigits(local.second)}';
}
