import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io';
import 'package:appflowy_editor/appflowy_editor.dart';

import '../ai/ai_summary_service.dart';
import '../data/note_repository.dart';
import '../domain/markdown.dart';
import '../domain/note.dart';
import '../sync/github_sync.dart';
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
  final folders = <String>{
    for (final note in notes)
      if (noteFolderLabel(note) case final folder?) folder,
  };
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
      final note = await ref.read(noteRepositoryProvider).getOrCreateToday();
      if (mounted) context.push('/editor/${Uri.encodeComponent(note.id)}');
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
    final result = await ref.read(syncEngineProvider).sync();
    if (!mounted) return;

    // The database watch normally updates the list after a pull. Invalidating
    // also makes a completed refresh visibly re-check the stream when the
    // remote contained no changes.
    ref.invalidate(notesProvider);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(result.message)));
  }

  Future<void> _generateMissingSummaries(List<Note> notes) async {
    final generator = ref.read(aiSummaryServiceProvider);
    if (!await generator.isConfigured()) return;
    for (final note in notes) {
      if (note.isPendingDeletion ||
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
        title: const Text('Specular'),
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
                data: (_) => notes.isEmpty
                    ? _RefreshableMessage(
                        allNotes.isEmpty
                            ? 'No notes yet. Tap the calendar to start today\'s note.'
                            : 'No notes in selected folders. Open View options to change them.',
                      )
                    : ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.only(bottom: 88),
                        itemCount: notes.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (_, index) =>
                            _NoteTile(note: notes[index]),
                      ),
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

class _NoteTile extends StatelessWidget {
  const _NoteTile({required this.note});
  final Note note;

  @override
  Widget build(BuildContext context) {
    final folder = noteFolderLabel(note);
    final summary = hasUsableSummary(note) ? note.summary! : '';
    return ListTile(
      title: Row(
        children: [
          if (note.isPinned)
            const Padding(
              padding: EdgeInsets.only(right: 6),
              child: Icon(Icons.push_pin, size: 16),
            ),
          Expanded(child: Text(note.title.isEmpty ? 'Untitled' : note.title)),
        ],
      ),
      subtitle: summary.isEmpty
          ? null
          : Text(summary, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: folder == null && !note.isConflict
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (note.isConflict)
                  const Icon(Icons.warning_amber_rounded, color: Colors.orange),
                if (note.isConflict && folder != null) const SizedBox(width: 8),
                if (folder != null) _FolderBadge(label: folder),
              ],
            ),
      onTap: () => context.push('/note/${Uri.encodeComponent(note.id)}'),
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
        if (!snapshot.hasData)
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        if (note == null)
          return const Scaffold(body: Center(child: Text('Note not found')));
        return Scaffold(
          appBar: AppBar(
            actions: [
              IconButton(
                tooltip: 'Generate AI summary',
                onPressed: () => _generateSummary(context, ref, note),
                icon: const Icon(Icons.auto_awesome),
              ),
              IconButton(
                onPressed: () =>
                    context.push('/editor/${Uri.encodeComponent(note.id)}'),
                icon: const Icon(Icons.edit),
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
      if (context.mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Summary: $summary')));
    } catch (error) {
      if (context.mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
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
      if (context.mounted)
        context.go('/note/${Uri.encodeComponent(renamed.id)}');
    } catch (error) {
      if (context.mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
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
              Text(
                'Summary',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
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
            onTapLink: (_, href, _) => _openLink(context, href),
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

  Future<void> _openLink(BuildContext context, String? href) async {
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

class _AttachmentImage extends ConsumerWidget {
  const _AttachmentImage({required this.notePath, required this.uri});
  final String notePath;
  final Uri uri;

  @override
  Widget build(BuildContext context, WidgetRef ref) => FutureBuilder<File?>(
    future: ref
        .read(noteRepositoryProvider)
        .resolveAttachment(notePath, uri.toString()),
    builder: (context, snapshot) {
      final file = snapshot.data;
      if (file == null)
        return const Padding(
          padding: EdgeInsets.all(8),
          child: Icon(Icons.broken_image_outlined),
        );
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Image.file(
          file,
          errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined),
        ),
      );
    },
  );
}

class EditorScreen extends ConsumerStatefulWidget {
  const EditorScreen({super.key, this.id, this.newTodo = false});
  final String? id;
  final bool newTodo;

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
  var _loading = true;
  var _saving = false;
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
    if (mounted) setState(() => _loading = false);
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
      if (mounted) setState(() => _stagedImages.add(staged));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Unable to add image: $error')));
      }
    }
  }

  @override
  void dispose() {
    unawaited(
      ref.read(noteRepositoryProvider).discardStagedImages(_stagedImages),
    );
    _editorState?.dispose();
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
          _note == null
              ? (widget.newTodo ? 'New to-do' : 'New note')
              : 'Edit note',
        ),
        actions: [
          IconButton(
            onPressed: _saving ? null : () => _addImage(ImageSource.camera),
            icon: const Icon(Icons.photo_camera),
          ),
          IconButton(
            onPressed: _saving ? null : () => _addImage(ImageSource.gallery),
            icon: const Icon(Icons.photo_library),
          ),
          IconButton(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const CircularProgressIndicator()
                : const Icon(Icons.done),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
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
        title: const Text('To-dos'),
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

/// Keeps a visible to-do list from jumping when a note update changes the
/// repository's default ordering. Items that arrive after the first result are
/// added in repository order, while existing items keep their place.
List<TodoItem> preserveTodoOrder(
  List<TodoItem> todos,
  List<TodoItem> previousOrder,
) {
  final todosById = {
    for (final todo in todos) (todo.noteId, todo.taskIndex): todo,
  };
  final previousIds = {
    for (final todo in previousOrder) (todo.noteId, todo.taskIndex),
  };
  return [
    for (final todo in previousOrder) ?todosById[(todo.noteId, todo.taskIndex)],
    for (final todo in todos)
      if (!previousIds.contains((todo.noteId, todo.taskIndex))) todo,
  ];
}

class _TodoListState extends ConsumerState<_TodoList> {
  var _previousOrder = <TodoItem>[];

  @override
  Widget build(BuildContext context) => ref
      .watch(todosProvider(widget.filter))
      .when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('$error')),
        data: (todos) {
          final orderedTodos = preserveTodoOrder(todos, _previousOrder);
          _previousOrder = orderedTodos;
          return ListView(
            children: [
              for (final todo in orderedTodos)
                _TodoRow(
                  key: ValueKey((todo.noteId, todo.taskIndex)),
                  todo: todo,
                ),
            ],
          );
        },
      );
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
                  const SizedBox(height: 2),
                  Text(
                    todo.noteTitle,
                    style: Theme.of(context).textTheme.bodySmall,
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
  const VoiceCaptureScreen({super.key});
  @override
  ConsumerState<VoiceCaptureScreen> createState() => _VoiceCaptureScreenState();
}

class _VoiceCaptureScreenState extends ConsumerState<VoiceCaptureScreen> {
  final _transcript = TextEditingController();
  var _recording = false;
  var _busy = false;
  var _asTodo = false;
  String? _error;

  Future<void> _start() async {
    try {
      await ref.read(voiceServiceProvider).start();
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
      if (mounted)
        setState(() {
          _transcript.text = transcript;
          _recording = false;
        });
    } catch (error) {
      if (mounted)
        setState(() {
          _recording = false;
          _error = '$error';
        });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (_transcript.text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      final note = await ref
          .read(noteRepositoryProvider)
          .appendToToday(
            _asTodo ? '- [ ] ${_transcript.text.trim()}' : _transcript.text,
          );
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
    ref.read(voiceServiceProvider).cancel();
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
            'Record a thought or to-do, then review its transcript before adding it to today.',
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
          if (_transcript.text.isEmpty) const Spacer(),
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
  static const _defaultVoiceModel = 'openai/gpt-4o-mini-transcribe';

  final _token = TextEditingController();
  final _owner = TextEditingController();
  final _repo = TextEditingController();
  final _aiUrl = TextEditingController();
  final _aiKey = TextEditingController();
  final _aiModel = TextEditingController();
  final _voiceModel = TextEditingController();
  final _voiceEndpoint = TextEditingController();
  final _voiceKey = TextEditingController();
  var _voiceProvider = 'OPENROUTER';
  var _usePreviewKey = true;
  var _loaded = false;
  var _saving = false;
  var _loadingRepositories = false;
  var _selectingRepository = false;
  String? _repositoryError;

  Future<void> _load() async {
    if (_loaded) return;
    _loaded = true;
    final storage = ref.read(secureStorageProvider);
    _token.text = await storage.read(key: 'github_token') ?? '';
    _owner.text = await storage.read(key: 'repo_owner') ?? '';
    _repo.text = await storage.read(key: 'repo_name') ?? '';
    _aiUrl.text = await storage.read(key: 'ai_provider_url') ?? '';
    _aiKey.text = await storage.read(key: 'ai_provider_api_key') ?? '';
    _aiModel.text =
        await storage.read(key: 'ai_provider_model_id') ?? _defaultSummaryModel;
    _voiceProvider = await storage.read(key: 'voice_provider') ?? 'OPENROUTER';
    _voiceModel.text =
        await storage.read(key: 'voice_model_id') ?? _defaultVoiceModel;
    _voiceEndpoint.text = await storage.read(key: 'voice_endpoint') ?? '';
    _voiceKey.text = await storage.read(key: 'voice_api_key') ?? '';
    _usePreviewKey =
        await storage.read(key: 'voice_use_preview_key') != 'false';
    if (mounted) setState(() {});
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final storage = ref.read(secureStorageProvider);
      await storage.write(key: 'github_token', value: _token.text.trim());
      await storage.write(key: 'repo_owner', value: _owner.text.trim());
      await storage.write(key: 'repo_name', value: _repo.text.trim());
      await storage.write(key: 'ai_provider_url', value: _aiUrl.text.trim());
      await storage.write(
        key: 'ai_provider_api_key',
        value: _aiKey.text.trim(),
      );
      await storage.write(
        key: 'ai_provider_model_id',
        value: _aiModel.text.trim(),
      );
      await storage.write(key: 'voice_provider', value: _voiceProvider);
      await storage.write(
        key: 'voice_model_id',
        value: _voiceModel.text.trim(),
      );
      await storage.write(
        key: 'voice_endpoint',
        value: _voiceEndpoint.text.trim(),
      );
      await storage.write(key: 'voice_api_key', value: _voiceKey.text.trim());
      await storage.write(
        key: 'voice_use_preview_key',
        value: _usePreviewKey.toString(),
      );
      final sync = await ref.read(syncEngineProvider).sync();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Settings saved. ${sync.message}')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _setDarkMode(bool value) async {
    final mode = value ? ThemeMode.dark : ThemeMode.light;
    ref.read(themeModeControllerProvider).setThemeMode(mode);
    await ref
        .read(secureStorageProvider)
        .write(key: themeModeStorageKey, value: themeModeStorageValue(mode));
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
                    'Only repositories containing Markdown notes can be selected.',
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
              title: const Text('Voice transcription'),
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _voiceProvider,
                  items: const [
                    DropdownMenuItem(value: 'OPENAI', child: Text('OpenAI')),
                    DropdownMenuItem(
                      value: 'OPENROUTER',
                      child: Text('OpenRouter'),
                    ),
                    DropdownMenuItem(
                      value: 'CUSTOM_OPENAI_COMPATIBLE',
                      child: Text('Custom OpenAI-compatible'),
                    ),
                  ],
                  onChanged: (value) => setState(() => _voiceProvider = value!),
                ),
                TextField(
                  controller: _voiceModel,
                  decoration: const InputDecoration(labelText: 'Voice model'),
                ),
                TextField(
                  controller: _voiceEndpoint,
                  decoration: const InputDecoration(
                    labelText: 'Custom endpoint (only for custom)',
                  ),
                ),
                SwitchListTile(
                  value: _usePreviewKey,
                  onChanged: (value) => setState(() => _usePreviewKey = value),
                  title: const Text('Use AI summary API key'),
                ),
                if (!_usePreviewKey)
                  TextField(
                    controller: _voiceKey,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Voice API key',
                    ),
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
