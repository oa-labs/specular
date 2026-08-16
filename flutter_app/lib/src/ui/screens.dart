import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
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
import '../domain/note_search.dart';
import '../sync/github_sync.dart';
import '../sync/sync_scheduler.dart';
import '../voice/voice_service.dart';
import '../platform/document_bridge.dart';
import '../platform/platform_capabilities.dart';
import 'note_body_editor.dart';
import 'specular_app.dart';

enum NoteListSort { lastUpdated, alphabetical }

/// The small, stable set of home views. Folders remain available when creating
/// notes, but are deliberately not promoted into the primary navigation.
enum NoteListView { all, notes, meetings, people }

enum NoteObjectType { note, meeting, person }

class MeetingDateGroup {
  const MeetingDateGroup({required this.date, required this.notes});

  final DateTime date;
  final List<Note> notes;
}

/// Image sources exposed by the editor. macOS deliberately presents only the
/// file chooser because image_picker's camera source needs a native delegate.
enum EditorImageAction { camera, gallery }

List<EditorImageAction> editorImageActions(PlatformCapabilities capabilities) =>
    capabilities.supportsCameraImport
    ? const [EditorImageAction.camera, EditorImageAction.gallery]
    : const [EditorImageAction.gallery];

String syncScheduleDescription(PlatformCapabilities capabilities) =>
    capabilities.supportsBestEffortInProcessSync
    ? 'While Specular is open, it checks at the selected interval. macOS may delay this work and it does not run after you quit the app.'
    : 'Sync runs at the selected cadence when Android permits network work.';

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

String formatDailyDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

/// Identifies the first-class note types supported by the home views.
///
/// Reflect libraries commonly use a body metadata line such as
/// `- Type: #meeting`. Earlier libraries may instead organize these notes in
/// `meetings/` and `people/`, so both forms are accepted during the transition.
NoteObjectType noteObjectType(Note note) {
  final metadataType = RegExp(
    r'^\s*[-*]\s*type\s*:\s*#?([\w-]+)\b',
    caseSensitive: false,
    multiLine: true,
  ).firstMatch(note.body)?.group(1)?.toLowerCase();
  if (metadataType == 'meeting' || metadataType == 'meetings') {
    return NoteObjectType.meeting;
  }
  if (metadataType == 'person' || metadataType == 'people') {
    return NoteObjectType.person;
  }

  switch (noteFolderLabel(note)?.toLowerCase()) {
    case 'meeting':
    case 'meetings':
      return NoteObjectType.meeting;
    case 'person':
    case 'people':
      return NoteObjectType.person;
    default:
      return NoteObjectType.note;
  }
}

bool noteMatchesView(Note note, NoteListView view) => switch (view) {
  NoteListView.all => true,
  NoteListView.notes => noteObjectType(note) == NoteObjectType.note,
  NoteListView.meetings => noteObjectType(note) == NoteObjectType.meeting,
  NoteListView.people => noteObjectType(note) == NoteObjectType.person,
};

/// Returns the first email address recorded for a person. Prefer the Reflect
/// metadata field, while accepting a plain address elsewhere in the note for
/// older person notes.
String? noteEmailAddress(Note note) {
  const email =
      r"[A-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Z0-9](?:[A-Z0-9-]{0,61}[A-Z0-9])?(?:\.[A-Z0-9](?:[A-Z0-9-]{0,61}[A-Z0-9])?)+";
  final fieldMatch = RegExp(
    '^\\s*[-*]?\\s*email\\s*:\\s*($email)',
    caseSensitive: false,
    multiLine: true,
  ).firstMatch(note.body);
  if (fieldMatch != null) return fieldMatch.group(1);
  return RegExp(email, caseSensitive: false).firstMatch(note.body)?.group(0);
}

/// Returns the date encoded in a meeting title when it is unambiguous.
///
/// Imported Markdown notes do not retain their original filesystem timestamp,
/// so [Note.updatedAt] often represents the import date. Meeting titles are a
/// more durable source when they include a complete date. We accept the common
/// ISO, US numeric, and written-month forms, including ordinal days and compact
/// names such as `DesignReviewJuly15,2026`. Incomplete or invalid dates return
/// null rather than guessing.
DateTime? meetingDateFromTitle(String title) {
  final normalized = title.trim();
  if (normalized.isEmpty) return null;

  DateTime? dateFromParts(String year, String month, String day) {
    final parsedYear = int.tryParse(year);
    final parsedMonth = int.tryParse(month);
    final parsedDay = int.tryParse(day);
    if (parsedYear == null || parsedMonth == null || parsedDay == null) {
      return null;
    }
    final date = DateTime(parsedYear, parsedMonth, parsedDay);
    return date.year == parsedYear &&
            date.month == parsedMonth &&
            date.day == parsedDay
        ? date
        : null;
  }

  final iso = RegExp(
    r'(?<!\d)(\d{4})[./-](\d{1,2})[./-](\d{1,2})(?!\d)',
  ).firstMatch(normalized);
  if (iso != null) {
    return dateFromParts(iso.group(1)!, iso.group(2)!, iso.group(3)!);
  }

  // Numeric month/day/year titles are intentionally interpreted as US format,
  // matching the product's existing written-date conventions.
  final numeric = RegExp(
    r'(?<!\d)(\d{1,2})[./-](\d{1,2})[./-](\d{4})(?!\d)',
  ).firstMatch(normalized);
  if (numeric != null) {
    return dateFromParts(
      numeric.group(3)!,
      numeric.group(1)!,
      numeric.group(2)!,
    );
  }

  const months = <String, int>{
    'jan': 1,
    'january': 1,
    'feb': 2,
    'february': 2,
    'mar': 3,
    'march': 3,
    'apr': 4,
    'april': 4,
    'may': 5,
    'jun': 6,
    'june': 6,
    'jul': 7,
    'july': 7,
    'aug': 8,
    'august': 8,
    'sep': 9,
    'sept': 9,
    'september': 9,
    'oct': 10,
    'october': 10,
    'nov': 11,
    'november': 11,
    'dec': 12,
    'december': 12,
  };
  final monthNames = months.keys.join('|');
  final writtenMonthFirst = RegExp(
    '($monthNames)\\.?[\\s,_-]*(\\d{1,2})(?:st|nd|rd|th)?[\\s,_-]+(\\d{4})(?!\\d)',
    caseSensitive: false,
  ).firstMatch(normalized);
  if (writtenMonthFirst != null) {
    return dateFromParts(
      writtenMonthFirst.group(3)!,
      months[writtenMonthFirst.group(1)!.toLowerCase()]!.toString(),
      writtenMonthFirst.group(2)!,
    );
  }

  final writtenDayFirst = RegExp(
    r'(?<!\d)(\d{1,2})(?:st|nd|rd|th)?[\s,_-]+(' +
        monthNames +
        r')\.?[\s,_-]+(\d{4})(?!\d)',
    caseSensitive: false,
  ).firstMatch(normalized);
  if (writtenDayFirst != null) {
    return dateFromParts(
      writtenDayFirst.group(3)!,
      months[writtenDayFirst.group(2)!.toLowerCase()]!.toString(),
      writtenDayFirst.group(1)!,
    );
  }

  return null;
}

/// Prefers the date recorded in the meeting title, falling back to the local
/// update timestamp for older notes that do not use the title-date convention.
DateTime meetingDate(Note note) =>
    meetingDateFromTitle(note.title) ?? DateUtils.dateOnly(note.updatedAt);

List<MeetingDateGroup> groupMeetingsByDate(Iterable<Note> notes) {
  final groups = <DateTime, List<Note>>{};
  for (final note in notes) {
    final date = meetingDate(note);
    (groups[date] ??= []).add(note);
  }
  final dates = groups.keys.toList()..sort((a, b) => b.compareTo(a));
  return [
    for (final date in dates)
      MeetingDateGroup(date: date, notes: groups[date]!),
  ];
}

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
  Set<String> deselectedFolders = const {},
  NoteListView view = NoteListView.all,
}) {
  final visible = notes
      .where(
        (note) =>
            noteMatchesView(note, view) &&
            !deselectedFolders.contains(noteFolderLabel(note)),
      )
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
  var _sort = NoteListSort.lastUpdated;
  var _loadedPreferences = false;
  var _createExpanded = false;
  var _openingToday = false;
  var _onboardingComplete = false;
  var _backupPromptDismissed = false;
  final _summaryJobs = <String>{};

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    if (!mounted) return;
    setState(() => _loadedPreferences = true);
    _loadFirstRunState();
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
    ref.invalidate(backupStatusProvider);
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

  void _showViewOptions() {
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
                    const Text('Choose how notes are ordered in each view.'),
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
    final selectedView = ref.watch(homeSelectedViewProvider);
    final backupStatus = ref.watch(backupStatusProvider).asData?.value;
    final notesState = ref.watch(notesProvider);
    final allNotes = notesState.asData?.value ?? const <Note>[];
    if (notesState.hasValue) unawaited(_generateMissingSummaries(allNotes));
    final notes = sortAndFilterNotes(allNotes, sort: _sort, view: selectedView);
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
          if (usesWideLayout(context))
            PopupMenuButton<String>(
              tooltip: 'Create',
              icon: const Icon(Icons.add),
              onSelected: (route) => context.push(route),
              itemBuilder: (_) => const [
                PopupMenuItem(value: '/editor/new', child: Text('New note')),
                PopupMenuItem(value: '/editor/todo', child: Text('New to-do')),
                PopupMenuItem(value: '/voice', child: Text('Voice capture')),
              ],
            ),
          PopupMenuButton<_HomeAction>(
            tooltip: 'More actions',
            onSelected: (action) {
              switch (action) {
                case _HomeAction.viewOptions:
                  _showViewOptions();
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
              child: const Icon(Icons.more_vert),
            ),
          ),
        ],
      ),
      body: !_loadedPreferences || notesState.isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _HomeViewSelector(
                  selectedView: selectedView,
                  onSelected: (view) =>
                      ref.read(homeSelectedViewProvider.notifier).state = view,
                ),
                Expanded(
                  child: RefreshIndicator(
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
                                : 'No ${selectedView.name} yet.',
                          );
                        }
                        return _HomeNoteList(
                          notes: notes,
                          selectedView: selectedView,
                          showBackupPrompt:
                              backupStatus?.kind ==
                                  BackupStatusKind.localOnly &&
                              !_backupPromptDismissed,
                          backupStatus: backupStatus,
                          onOpenSettings: () => context.push('/settings'),
                          onDismissBackupPrompt: _dismissBackupPrompt,
                        );
                      },
                      error: (error, _) =>
                          _RefreshableMessage('Unable to load notes: $error'),
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                    ),
                  ),
                ),
              ],
            ),
      floatingActionButton: usesWideLayout(context)
          ? null
          : Column(
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
                  tooltip: _createExpanded
                      ? 'Close create menu'
                      : 'Create new item',
                  onPressed: () =>
                      setState(() => _createExpanded = !_createExpanded),
                  child: Icon(_createExpanded ? Icons.close : Icons.add),
                ),
              ],
            ),
    );
  }
}

enum _HomeAction { viewOptions, settings }

class _HomeViewSelector extends StatelessWidget {
  const _HomeViewSelector({
    required this.selectedView,
    required this.onSelected,
  });

  final NoteListView selectedView;
  final ValueChanged<NoteListView> onSelected;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
    child: SegmentedButton<NoteListView>(
      segments: const [
        ButtonSegment(value: NoteListView.notes, label: Text('Notes')),
        ButtonSegment(
          value: NoteListView.meetings,
          label: Text('Meetings', softWrap: false),
        ),
        ButtonSegment(value: NoteListView.people, label: Text('People')),
        ButtonSegment(value: NoteListView.all, label: Text('All')),
      ],
      selected: {selectedView},
      showSelectedIcon: false,
      style: const ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        ),
        textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 13)),
      ),
      onSelectionChanged: (selection) => onSelected(selection.first),
    ),
  );
}

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

class _HomeNoteList extends StatelessWidget {
  const _HomeNoteList({
    required this.notes,
    required this.selectedView,
    required this.showBackupPrompt,
    required this.backupStatus,
    required this.onOpenSettings,
    required this.onDismissBackupPrompt,
  });

  final List<Note> notes;
  final NoteListView selectedView;
  final bool showBackupPrompt;
  final BackupStatus? backupStatus;
  final VoidCallback onOpenSettings;
  final VoidCallback onDismissBackupPrompt;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      if (showBackupPrompt)
        _BackupStatusCard(
          status: backupStatus!,
          onOpenSettings: onOpenSettings,
          onDismiss: onDismissBackupPrompt,
        ),
    ];
    if (selectedView == NoteListView.meetings) {
      for (final group in groupMeetingsByDate(notes)) {
        children.add(_MeetingDateHeader(date: group.date));
        for (final note in group.notes) {
          children
            ..add(_NoteTile(key: ValueKey(note.id), note: note))
            ..add(const Divider(height: 1));
        }
      }
    } else {
      for (final note in notes) {
        children
          ..add(
            _NoteTile(
              key: ValueKey(note.id),
              note: note,
              showPersonEmail: selectedView == NoteListView.people,
            ),
          )
          ..add(const Divider(height: 1));
      }
    }
    if (children.last is Divider) children.removeLast();
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 88),
      children: children,
    );
  }
}

class _MeetingDateHeader extends StatelessWidget {
  const _MeetingDateHeader({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
    child: Text(
      MaterialLocalizations.of(context).formatMediumDate(date),
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
  );
}

class _NoteTile extends ConsumerStatefulWidget {
  const _NoteTile({
    super.key,
    required this.note,
    this.showPersonEmail = false,
    this.searchQuery,
    this.searchExcerpt,
  });
  final Note note;
  final bool showPersonEmail;
  final NoteSearchQuery? searchQuery;
  final String? searchExcerpt;

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

  Future<void> _openEmail(String email) async {
    final opened = await launchUrl(
      Uri(scheme: 'mailto', path: email),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Unable to open email')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final note = widget.note;
    final type = noteObjectType(note);
    final summary = hasUsableSummary(note) ? note.summary! : '';
    final email = widget.searchExcerpt == null && widget.showPersonEmail
        ? noteEmailAddress(note)
        : null;
    final secondaryText =
        widget.searchExcerpt ??
        (widget.showPersonEmail ? email ?? '' : summary);
    final hasMetadata = note.isConflict || email != null;
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
                    _NoteKindIcons(note: note, type: type),
                    Expanded(
                      child: _HighlightedText(
                        text: note.title.isEmpty ? 'Untitled' : note.title,
                        query: widget.searchQuery,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    if (_isPinned)
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Tooltip(
                          message: 'Pinned',
                          child: Icon(
                            Icons.push_pin,
                            size: 20,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                  ],
                ),
                if (secondaryText.isNotEmpty || hasMetadata)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (secondaryText.isNotEmpty)
                          Expanded(
                            child: email == null
                                ? _HighlightedText(
                                    text: secondaryText,
                                    query: widget.searchQuery,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  )
                                : Semantics(
                                    link: true,
                                    label: 'Email $email',
                                    child: GestureDetector(
                                      onTap: () => _openEmail(email),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Flexible(
                                            child: Text(
                                              email,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: theme.textTheme.bodyMedium
                                                  ?.copyWith(
                                                    color: theme
                                                        .colorScheme
                                                        .primary,
                                                    decoration: TextDecoration
                                                        .underline,
                                                  ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                          ),
                        if (secondaryText.isNotEmpty && note.isConflict)
                          const SizedBox(width: 8),
                        if (note.isConflict)
                          const Icon(
                            Icons.warning_amber_rounded,
                            color: Colors.orange,
                          ),
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

class _HighlightedText extends StatelessWidget {
  const _HighlightedText({
    required this.text,
    required this.query,
    required this.style,
    required this.maxLines,
    required this.overflow,
  });

  final String text;
  final NoteSearchQuery? query;
  final TextStyle? style;
  final int maxLines;
  final TextOverflow overflow;

  @override
  Widget build(BuildContext context) {
    final search = query;
    if (search == null || search.isEmpty) {
      return Text(text, maxLines: maxLines, overflow: overflow, style: style);
    }
    final ranges = searchHighlightRanges(text, search);
    if (ranges.isEmpty) {
      return Text(text, maxLines: maxLines, overflow: overflow, style: style);
    }
    final highlightStyle = style?.copyWith(
      backgroundColor: Theme.of(context).colorScheme.tertiaryContainer,
      color: Theme.of(context).colorScheme.onTertiaryContainer,
      fontWeight: FontWeight.w700,
    );
    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final range in ranges) {
      if (cursor < range.$1) {
        spans.add(TextSpan(text: text.substring(cursor, range.$1)));
      }
      spans.add(
        TextSpan(
          text: text.substring(range.$1, range.$2),
          style: highlightStyle,
        ),
      );
      cursor = range.$2;
    }
    if (cursor < text.length) spans.add(TextSpan(text: text.substring(cursor)));
    return Text.rich(
      TextSpan(style: style, children: spans),
      maxLines: maxLines,
      overflow: overflow,
    );
  }
}

class _NoteKindIcons extends StatelessWidget {
  const _NoteKindIcons({required this.note, required this.type});

  final Note note;
  final NoteObjectType type;

  @override
  Widget build(BuildContext context) {
    final icons = <(IconData, String)>[
      if (type == NoteObjectType.meeting) (Icons.groups_outlined, 'Meeting'),
      if (type == NoteObjectType.person) (Icons.person_outline, 'Person'),
      if (note.isDaily) (Icons.calendar_today_outlined, 'Daily note'),
      if (type == NoteObjectType.note && !note.isDaily)
        (Icons.note_outlined, 'Note'),
    ];
    if (icons.isEmpty) return const SizedBox.shrink();
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (icon, label) in icons)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Tooltip(
                message: label,
                child: Icon(icon, size: 16, color: color),
              ),
            ),
        ],
      ),
    );
  }
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
        _NoteBacklinks(note: note),
        if (note.isDaily) _DailyTaskBacklinks(daily: note),
        Expanded(
          child: Markdown(
            data: NoteBodyEditorCodec.normalizeTaskListSpacing(
              MarkdownContract.renderWikiLinks(note.body),
            ),
            padding: const EdgeInsets.all(16),
            styleSheet: MarkdownStyleSheet.fromTheme(
              Theme.of(context),
            ).copyWith(p: Theme.of(context).textTheme.bodyLarge),
            // Match the editor: align the checkbox to the task text baseline.
            listItemCrossAxisAlignment:
                MarkdownListItemCrossAxisAlignment.baseline,
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
    final wikiTitle = MarkdownContract.wikiLinkTitle(href ?? '');
    if (wikiTitle != null) {
      final target = await ref
          .read(noteRepositoryProvider)
          .findByWikiLinkTitle(wikiTitle);
      if (target != null && context.mounted) {
        context.push('/note/${Uri.encodeComponent(target.id)}');
      } else if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Linked note is not available locally: $wikiTitle'),
          ),
        );
      }
      return;
    }

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

/// Incoming note links backed by the durable local link index. Daily task
/// schedule links render in their dedicated task panel instead.
class _NoteBacklinks extends ConsumerWidget {
  const _NoteBacklinks({required this.note});

  final Note note;

  @override
  Widget build(
    BuildContext context,
    WidgetRef ref,
  ) => StreamBuilder<List<NoteBacklink>>(
    stream: ref.read(noteRepositoryProvider).watchBacklinks(note),
    builder: (context, snapshot) {
      final backlinks = (snapshot.data ?? const <NoteBacklink>[])
          .where(
            (backlink) =>
                !note.isDaily || !TodoMarkdown.isDailyDate(backlink.label),
          )
          .toList();
      if (backlinks.isEmpty) return const SizedBox.shrink();
      return Container(
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
              'Backlinks',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 6),
            for (final backlink in backlinks)
              InkWell(
                onTap: () => context.push(
                  '/note/${Uri.encodeComponent(backlink.sourceNoteId)}',
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        backlink.sourceNoteTitle,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                      Text(
                        backlink.label,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}

/// Reflect-style incoming task links for a daily note. The actual checkbox
/// state lives in the source note, so this view always toggles that task
/// rather than copying it into the daily note.
class _DailyTaskBacklinks extends ConsumerWidget {
  const _DailyTaskBacklinks({required this.daily});

  final Note daily;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      StreamBuilder<List<ScheduledTaskBacklink>>(
        stream: ref
            .read(noteRepositoryProvider)
            .watchScheduledTaskBacklinks(daily),
        builder: (context, snapshot) {
          final backlinks = snapshot.data ?? const <ScheduledTaskBacklink>[];
          if (backlinks.isEmpty) return const SizedBox.shrink();
          final groups = <String, List<ScheduledTaskBacklink>>{};
          for (final backlink in backlinks) {
            groups.putIfAbsent(backlink.sourceNoteId, () => []).add(backlink);
          }
          return Container(
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
                  'Backlinks',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 6),
                for (final group in groups.values) ...[
                  InkWell(
                    onTap: () => context.push(
                      '/note/${Uri.encodeComponent(group.first.sourceNoteId)}',
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        group.first.sourceNoteTitle,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ),
                  for (final backlink in group)
                    _ScheduledBacklinkTask(backlink: backlink),
                ],
              ],
            ),
          );
        },
      );
}

class _ScheduledBacklinkTask extends ConsumerWidget {
  const _ScheduledBacklinkTask({required this.backlink});

  final ScheduledTaskBacklink backlink;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Checkbox(
          value: backlink.isCompleted,
          semanticLabel: 'Mark ${backlink.text} complete',
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
          onChanged: (_) => ref
              .read(noteRepositoryProvider)
              .toggleTodo(
                TodoItem(
                  noteId: backlink.sourceNoteId,
                  taskIndex: backlink.taskIndex,
                  text: backlink.text,
                  isCompleted: backlink.isCompleted,
                  noteTitle: backlink.sourceNoteTitle,
                ),
              ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: MarkdownBody(
              data: MarkdownContract.renderWikiLinks(backlink.text),
              styleSheet: MarkdownStyleSheet.fromTheme(
                Theme.of(context),
              ).copyWith(p: Theme.of(context).textTheme.bodyLarge),
              onTapLink: (_, href, _) => _openLink(context, ref, href),
            ),
          ),
        ),
      ],
    ),
  );

  Future<void> _openLink(
    BuildContext context,
    WidgetRef ref,
    String? href,
  ) async {
    final title = MarkdownContract.wikiLinkTitle(href ?? '');
    if (title == null) return;
    final target = await ref
        .read(noteRepositoryProvider)
        .findByWikiLinkTitle(title);
    if (target != null && context.mounted) {
      context.push('/note/${Uri.encodeComponent(target.id)}');
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
  late final _globalTaskMobileToolbarItem = MobileToolbarItem.action(
    itemIconBuilder: (context, _, _) =>
        Icon(Icons.task_alt, color: MobileToolbarTheme.of(context).iconColor),
    actionHandler: (_, editorState) => _toggleGlobalTask(editorState),
  );
  late final _scheduleTaskMobileToolbarItem = MobileToolbarItem.action(
    itemIconBuilder: (context, _, _) => Icon(
      Icons.calendar_month,
      color: MobileToolbarTheme.of(context).iconColor,
    ),
    actionHandler: (_, editorState) =>
        unawaited(_scheduleSelectedTask(editorState)),
  );
  late final _localCheckboxMobileToolbarItem = MobileToolbarItem.action(
    itemIconBuilder: (context, _, _) => Icon(
      Icons.check_box_outline_blank,
      color: MobileToolbarTheme.of(context).iconColor,
    ),
    actionHandler: (_, editorState) => _toggleLocalCheckbox(editorState),
  );

  late final _globalTaskToolbarItem = ToolbarItem(
    id: 'specular.global_task',
    group: 3,
    isActive: onlyShowInTextType,
    builder: (context, editorState, _, iconColor, tooltipBuilder) {
      final child = _desktopToolbarButton(
        icon: Icons.task_alt,
        color: iconColor,
        onPressed: () => unawaited(_toggleGlobalTask(editorState)),
      );
      return tooltipBuilder?.call(
            context,
            'specular.global_task',
            'Global task',
            child,
          ) ??
          child;
    },
  );
  late final _scheduleTaskToolbarItem = ToolbarItem(
    id: 'specular.schedule_task',
    group: 3,
    isActive: onlyShowInTextType,
    builder: (context, editorState, _, iconColor, tooltipBuilder) {
      final child = _desktopToolbarButton(
        icon: Icons.calendar_month,
        color: iconColor,
        onPressed: () => unawaited(_scheduleSelectedTask(editorState)),
      );
      return tooltipBuilder?.call(
            context,
            'specular.schedule_task',
            'Schedule task',
            child,
          ) ??
          child;
    },
  );
  late final _localCheckboxToolbarItem = ToolbarItem(
    id: 'specular.local_checkbox',
    group: 3,
    isActive: onlyShowInTextType,
    builder: (context, editorState, _, iconColor, tooltipBuilder) {
      final child = _desktopToolbarButton(
        icon: Icons.check_box_outline_blank,
        color: iconColor,
        onPressed: () => unawaited(_toggleLocalCheckbox(editorState)),
      );
      return tooltipBuilder?.call(
            context,
            'specular.local_checkbox',
            'Note checkbox',
            child,
          ) ??
          child;
    },
  );

  static Widget _desktopToolbarButton({
    required IconData icon,
    required Color? color,
    required VoidCallback onPressed,
  }) => SizedBox.square(
    dimension: 32,
    child: IconButton(
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      tooltip: null,
      color: color,
      icon: Icon(icon, size: 18),
      onPressed: onPressed,
    ),
  );

  static Future<void> _toggleGlobalTask(EditorState editorState) async {
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
  }

  static Future<void> _toggleLocalCheckbox(EditorState editorState) async {
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
  }

  final _title = TextEditingController();
  Note? _note;
  EditorState? _editorState;
  EditorScrollController? _wideEditorScrollController;
  final _stagedImages = <StagedImage>[];
  final _editorFocus = FocusNode(debugLabel: 'note editor');
  var _loading = true;
  var _saving = false;
  var _voiceRecording = false;
  var _willRewriteUnsupportedMarkdown = false;
  DateTime? _scheduledFor;
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
    _wideEditorScrollController = EditorScrollController(
      editorState: _editorState!,
      shrinkWrap: false,
    );
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
          ? await repo.appendToToday(body, scheduledFor: _scheduledFor)
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
    // The picker's search field takes focus, which can clear AppFlowy's
    // selection before the sheet returns. Keep the cursor so the link lands
    // where the user invoked this action.
    final retainedSelection = _editorState?.selection;
    final selected = await showModalBottomSheet<Note>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _WikiLinkPicker(excludingId: _note?.id),
    );
    final editorState = _editorState;
    if (selected == null || editorState == null || !mounted) return;
    await NoteBodyEditorCodec.insertTextAtSelectionOrEnd(
      editorState,
      selected.title,
      retainedSelection: retainedSelection,
      attributes: {
        AppFlowyRichTextKeys.href: MarkdownContract.wikiLinkHref(
          selected.title,
        ),
      },
    );
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _editorFocus.requestFocus();
      });
    }
  }

  Future<void> _chooseNewTodoSchedule() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _scheduledFor ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (selected != null && mounted) setState(() => _scheduledFor = selected);
  }

  int? _selectedGlobalTaskIndex(EditorState editorState) {
    final selection = editorState.selection;
    if (selection == null) return null;
    final selected = editorState.getNodeAtPath(selection.start.path);
    if (selected == null ||
        selected.type != TodoListBlockKeys.type ||
        selected.attributes[NoteBodyEditorCodec.globalTaskAttribute] != true) {
      return null;
    }
    var globalIndex = 0;
    for (final node in editorState.document.root.children) {
      if (node.type != TodoListBlockKeys.type ||
          node.attributes[NoteBodyEditorCodec.globalTaskAttribute] != true) {
        continue;
      }
      if (listEquals(node.path, selected.path)) return globalIndex;
      globalIndex++;
    }
    return null;
  }

  Future<void> _scheduleSelectedTask(EditorState editorState) async {
    final taskIndex = _selectedGlobalTaskIndex(editorState);
    if (taskIndex == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Place the cursor in a global task first.'),
          ),
        );
      }
      return;
    }
    if (_note == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Save this note before scheduling a task.'),
          ),
        );
      }
      return;
    }
    final selected = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (selected == null || !mounted) return;
    setState(() => _saving = true);
    try {
      final repository = ref.read(noteRepositoryProvider);
      final saved = await repository.save(
        _note!,
        title: _title.text,
        body: NoteBodyEditorCodec.export(editorState),
      );
      await repository.scheduleGlobalTask(
        noteId: saved.id,
        taskIndex: taskIndex,
        date: selected,
      );
      _note = await repository.get(saved.id);
      _editorState?.dispose();
      _wideEditorScrollController?.dispose();
      _editorState = await NoteBodyEditorCodec.load(_note, repository);
      _wideEditorScrollController = EditorScrollController(
        editorState: _editorState!,
        shrinkWrap: false,
      );
      ref.invalidate(notesProvider);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to schedule task: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _buildEditor(BuildContext context, {required bool wideLayout}) {
    final editor = AppFlowyEditor(
      editorState: _editorState!,
      focusNode: _editorFocus,
      autoFocus: false,
      editorScrollController: wideLayout ? _wideEditorScrollController : null,
      // A wide layout gets desktop selection behavior and a readable maximum
      // line length, even when it is running on an Android tablet.
      editorStyle: wideLayout
          ? EditorStyle.desktop(
              maxWidth: 760,
              padding: const EdgeInsets.symmetric(horizontal: 32),
              cursorColor: Theme.of(context).colorScheme.primary,
              textStyleConfiguration: TextStyleConfiguration(
                text: Theme.of(context).textTheme.bodyLarge!,
              ),
              textSpanDecorator: _linkTextSpanDecorator(wideLayout: wideLayout),
            )
          : EditorStyle.mobile(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              cursorColor: Theme.of(context).colorScheme.primary,
              textStyleConfiguration: TextStyleConfiguration(
                text: Theme.of(context).textTheme.bodyLarge!,
              ),
              textSpanDecorator: _linkTextSpanDecorator(wideLayout: wideLayout),
            ),
      // A zero edge avoids AppFlowy's automatic edge-scroll loop on long
      // notes while retaining ordinary touch and trackpad scrolling.
      autoScrollEdgeOffset: 0,
    );
    if (!wideLayout) {
      return MobileToolbarV2(
        editorState: _editorState!,
        toolbarItems: [
          headingMobileToolbarItem,
          textDecorationMobileToolbarItemV2,
          codeMobileToolbarItem,
          linkMobileToolbarItem,
          listMobileToolbarItem,
          _globalTaskMobileToolbarItem,
          _scheduleTaskMobileToolbarItem,
          _localCheckboxMobileToolbarItem,
          quoteMobileToolbarItem,
          dividerMobileToolbarItem,
        ],
        child: editor,
      );
    }
    return FloatingToolbar(
      editorState: _editorState!,
      editorScrollController: _wideEditorScrollController!,
      textDirection: Directionality.of(context),
      style: FloatingToolbarStyle(
        backgroundColor: Theme.of(context).colorScheme.inverseSurface,
        toolbarActiveColor: Theme.of(context).colorScheme.primary,
        toolbarIconColor: Theme.of(context).colorScheme.onInverseSurface,
      ),
      tooltipBuilder: (context, _, message, child) =>
          Tooltip(message: message, preferBelow: false, child: child),
      items: [
        paragraphItem,
        ...headingItems,
        ...markdownFormatItems,
        quoteItem,
        bulletedListItem,
        numberedListItem,
        _globalTaskToolbarItem,
        _scheduleTaskToolbarItem,
        _localCheckboxToolbarItem,
        linkItem,
      ],
      child: editor,
    );
  }

  TextSpanDecoratorForAttribute _linkTextSpanDecorator({
    required bool wideLayout,
  }) => (context, node, index, text, before, after) {
    final wikiTitle = MarkdownContract.wikiLinkTitle(
      text.attributes?[AppFlowyRichTextKeys.href] as String? ?? '',
    );
    if (wikiTitle == null) {
      return wideLayout
          ? defaultTextSpanDecoratorForAttribute(
              context,
              node,
              index,
              text,
              before,
              after,
            )
          : mobileTextSpanDecoratorForAttribute(
              context,
              node,
              index,
              text,
              before,
              after,
            );
    }
    return TextSpan(
      style: before.style?.copyWith(
        color: Theme.of(context).colorScheme.primary,
        decoration: TextDecoration.underline,
      ),
      text: text.text,
      mouseCursor: SystemMouseCursors.click,
      recognizer: TapGestureRecognizer()
        ..onTap = () => unawaited(_openWikiLink(wikiTitle)),
    );
  };

  Future<void> _openWikiLink(String title) async {
    final target = await ref
        .read(noteRepositoryProvider)
        .findByWikiLinkTitle(title);
    if (!mounted) return;
    if (target == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Linked note is not available locally: $title')),
      );
      return;
    }
    context.push('/note/${Uri.encodeComponent(target.id)}');
  }

  @override
  void dispose() {
    unawaited(
      ref.read(noteRepositoryProvider).discardStagedImages(_stagedImages),
    );
    _wideEditorScrollController?.dispose();
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
    final isNewRegularNote =
        widget.id == null && !widget.newTodo && widget.dailyDate == null;
    // On compact phone layouts, the New note label crowds the editor actions
    // and is truncated. The title field below already conveys the note's
    // identity, so reserve the app bar space for controls instead.
    final appBarTitle = isNewRegularNote && !usesWideLayout(context)
        ? null
        : Text(
            widget.newTodo
                ? 'New to-do'
                : _note == null
                ? 'New note'
                : 'Edit note',
          );
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): () =>
            unawaited(_save()),
      },
      child: Scaffold(
        appBar: AppBar(
          title: appBarTitle,
          actions: [
            IconButton(
              tooltip: 'Insert wiki link',
              onPressed: _saving || _loading ? null : _insertWikiLink,
              icon: const Icon(Icons.link),
            ),
            for (final action in editorImageActions(
              PlatformCapabilities.current,
            ))
              IconButton(
                tooltip: action == EditorImageAction.camera
                    ? 'Take photo'
                    : PlatformCapabilities.current.isDesktop
                    ? 'Choose image…'
                    : 'Choose from gallery',
                onPressed: _saving
                    ? null
                    : () => _addImage(
                        action == EditorImageAction.camera
                            ? ImageSource.camera
                            : ImageSource.gallery,
                      ),
                icon: Icon(
                  action == EditorImageAction.camera
                      ? Icons.photo_camera
                      : Icons.photo_library,
                ),
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
                    if (widget.newTodo)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextButton.icon(
                              onPressed: _saving
                                  ? null
                                  : _chooseNewTodoSchedule,
                              icon: const Icon(Icons.calendar_month),
                              label: Text(
                                _scheduledFor == null
                                    ? 'Schedule for a day'
                                    : 'Scheduled: ${formatDailyDate(_scheduledFor!)}',
                              ),
                            ),
                            if (_scheduledFor != null)
                              IconButton(
                                tooltip: 'Clear schedule',
                                icon: const Icon(Icons.close),
                                onPressed: _saving
                                    ? null
                                    : () =>
                                          setState(() => _scheduledFor = null),
                              ),
                          ],
                        ),
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
                            color: Theme.of(
                              context,
                            ).colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Expanded(
                      child: _buildEditor(
                        context,
                        wideLayout: usesWideLayout(context),
                      ),
                    ),
                  ],
                ),
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
  var _scope = NoteSearchScope.all;

  NoteSearchQuery get _search => NoteSearchQuery(_query, scope: _scope);

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: TextField(
        autofocus: true,
        onChanged: (value) => setState(() => _query = value),
        decoration: const InputDecoration(hintText: 'Search notes'),
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(52),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: SegmentedButton<NoteSearchScope>(
            segments: const [
              ButtonSegment(value: NoteSearchScope.all, label: Text('All')),
              ButtonSegment(
                value: NoteSearchScope.title,
                label: Text('Titles'),
              ),
              ButtonSegment(value: NoteSearchScope.body, label: Text('Body')),
            ],
            selected: {_scope},
            onSelectionChanged: (selection) =>
                setState(() => _scope = selection.single),
          ),
        ),
      ),
    ),
    body: StreamBuilder<List<NoteSearchResult>>(
      stream: ref.read(noteRepositoryProvider).searchResults(_search),
      builder: (_, snapshot) {
        final results = snapshot.data ?? const <NoteSearchResult>[];
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (results.isEmpty && !_search.isEmpty) {
          return const Center(child: Text('No matching notes'));
        }
        return ListView(
          children: [
            for (final result in results)
              _NoteTile(
                note: result.note,
                searchQuery: _search,
                searchExcerpt: result.excerpt,
              ),
          ],
        );
      },
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
        title: Text('To-dos'),
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

class _TodoRow extends ConsumerStatefulWidget {
  const _TodoRow({super.key, required this.todo});
  final TodoItem todo;

  @override
  ConsumerState<_TodoRow> createState() => _TodoRowState();
}

class _TodoRowState extends ConsumerState<_TodoRow> {
  late final TextEditingController _editor;
  late final FocusNode _editorFocus;
  var _editing = false;
  var _saving = false;

  TodoItem get _todo => widget.todo;

  @override
  void initState() {
    super.initState();
    _editor = TextEditingController(
      text: TodoMarkdown.editableText(_todo.text),
    );
    _editorFocus = FocusNode();
  }

  @override
  void didUpdateWidget(covariant _TodoRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_editing && oldWidget.todo.text != _todo.text) {
      _editor.text = TodoMarkdown.editableText(_todo.text);
    }
  }

  @override
  void dispose() {
    _editor.dispose();
    _editorFocus.dispose();
    super.dispose();
  }

  void _startEditing() {
    setState(() => _editing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _editorFocus.requestFocus();
      _editor.selection = TextSelection.collapsed(offset: _editor.text.length);
    });
  }

  Future<void> _saveText() async {
    if (_saving) return;
    final text = _editor.text.trim();
    if (text.isEmpty) {
      _editor.text = TodoMarkdown.editableText(_todo.text);
      if (mounted) setState(() => _editing = false);
      return;
    }
    if (text == TodoMarkdown.editableText(_todo.text)) {
      if (mounted) setState(() => _editing = false);
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(noteRepositoryProvider).updateTodoText(_todo, text);
      if (mounted) setState(() => _editing = false);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to update task: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _schedule() async {
    final current = TodoMarkdown.scheduledDate(_todo.text);
    final selected = await showDatePicker(
      context: context,
      initialDate: current == null ? DateTime.now() : DateTime.parse(current),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (selected == null || !mounted) return;
    try {
      await ref
          .read(noteRepositoryProvider)
          .scheduleGlobalTask(
            noteId: _todo.noteId,
            taskIndex: _todo.taskIndex,
            date: selected,
          );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to schedule task: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          // Align the checkbox glyph with the first line, rather than centering
          // it beside a task that wraps over several lines.
          padding: const EdgeInsets.only(top: 1, right: 8),
          child: Checkbox(
            value: _todo.isCompleted,
            semanticLabel: 'Mark ${_todo.text} complete',
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
            onChanged: _saving
                ? null
                : (_) => ref.read(noteRepositoryProvider).toggleTodo(_todo),
          ),
        ),
        Expanded(
          child: _editing
              ? TextField(
                  controller: _editor,
                  focusNode: _editorFocus,
                  enabled: !_saving,
                  minLines: 1,
                  maxLines: null,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => unawaited(_saveText()),
                  onTapOutside: (_) => unawaited(_saveText()),
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'Task text',
                  ),
                )
              : InkWell(
                  onTap: _startEditing,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 6),
                    child: MarkdownBody(
                      data: MarkdownContract.renderWikiLinks(_todo.text),
                      styleSheet: MarkdownStyleSheet.fromTheme(
                        Theme.of(context),
                      ).copyWith(p: Theme.of(context).textTheme.bodyLarge),
                      onTapLink: (_, href, _) =>
                          _openTaskLink(context, ref, href),
                    ),
                  ),
                ),
        ),
        if (_editing)
          IconButton(
            tooltip: 'Save task text',
            onPressed: _saving ? null : () => unawaited(_saveText()),
            icon: _saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.done),
          ),
        IconButton(
          tooltip: TodoMarkdown.scheduledDate(_todo.text) == null
              ? 'Schedule task'
              : 'Reschedule task',
          onPressed: _saving ? null : () => unawaited(_schedule()),
          icon: const Icon(Icons.calendar_month),
        ),
      ],
    ),
  );

  Future<void> _openTaskLink(
    BuildContext context,
    WidgetRef ref,
    String? href,
  ) async {
    final title = MarkdownContract.wikiLinkTitle(href ?? '');
    if (title == null) return;
    final target = await ref
        .read(noteRepositoryProvider)
        .findByWikiLinkTitle(title);
    if (target != null && context.mounted) {
      context.push('/note/${Uri.encodeComponent(target.id)}');
    }
  }
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

enum _SettingsSection { appearance, backup, ai, voice }

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
  var _section = _SettingsSection.appearance;
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
        ref.invalidate(backupStatusProvider);
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
      ref.invalidate(backupStatusProvider);
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

  Future<void> _setTextScale(double scale) async {
    ref.read(textScaleControllerProvider).setTextScale(scale);
    await ref
        .read(secureStorageProvider)
        .write(key: textScaleStorageKey, value: scale.toString());
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
      ref.invalidate(backupStatusProvider);
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
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isDesktopSettings =
                PlatformCapabilities.current.isDesktop &&
                constraints.maxWidth >= 780;
            final content = _sectionContent(context);
            if (!isDesktopSettings) {
              return Column(
                children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SegmentedButton<_SettingsSection>(
                      segments: _SettingsSection.values
                          .map(
                            (section) => ButtonSegment(
                              value: section,
                              icon: Icon(_sectionIcon(section)),
                              label: Text(_sectionTitle(section)),
                            ),
                          )
                          .toList(),
                      selected: {_section},
                      onSelectionChanged: (selected) =>
                          setState(() => _section = selected.first),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(child: content),
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                NavigationRail(
                  extended: true,
                  minExtendedWidth: 196,
                  selectedIndex: _section.index,
                  labelType: NavigationRailLabelType.none,
                  destinations: [
                    for (final section in _SettingsSection.values)
                      NavigationRailDestination(
                        icon: Icon(_sectionIcon(section)),
                        selectedIcon: Icon(_sectionIcon(section)),
                        label: Text(_sectionTitle(section)),
                      ),
                  ],
                  onDestinationSelected: (index) =>
                      setState(() => _section = _SettingsSection.values[index]),
                ),
                const VerticalDivider(width: 32),
                Expanded(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: content,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  IconData _sectionIcon(_SettingsSection section) => switch (section) {
    _SettingsSection.appearance => Icons.tune,
    _SettingsSection.backup => Icons.cloud_sync_outlined,
    _SettingsSection.ai => Icons.auto_awesome_outlined,
    _SettingsSection.voice => Icons.mic_none_outlined,
  };

  String _sectionTitle(_SettingsSection section) => switch (section) {
    _SettingsSection.appearance => 'Appearance',
    _SettingsSection.backup => 'Backup & sync',
    _SettingsSection.ai => 'AI summaries',
    _SettingsSection.voice => 'Voice',
  };

  Widget _sectionContent(BuildContext context) => switch (_section) {
    _SettingsSection.appearance => _appearanceSection(context),
    _SettingsSection.backup => _backupSection(context),
    _SettingsSection.ai => _aiSection(context),
    _SettingsSection.voice => _voiceSection(context),
  };

  Widget _appearanceSection(BuildContext context) => ListView(
    children: [
      const _SettingsSectionHeader(
        title: 'Appearance',
        description: 'Choose how Specular looks and how large its text feels.',
      ),
      _SettingsGroup(
        children: [
          SwitchListTile(
            value:
                ref.watch(themeModeControllerProvider).themeMode ==
                ThemeMode.dark,
            onChanged: _setDarkMode,
            secondary: const Icon(Icons.dark_mode_outlined),
            title: const Text('Dark mode'),
            subtitle: const Text('Turn off for light mode.'),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.format_size),
            title: const Text('Font size'),
            subtitle: const Text('Applies to the interface and your notes.'),
            trailing: DropdownButton<double>(
              value: ref.watch(textScaleControllerProvider).textScale,
              onChanged: (scale) {
                if (scale != null) _setTextScale(scale);
              },
              items: const [
                DropdownMenuItem(value: 0.9, child: Text('Small')),
                DropdownMenuItem(value: 1.0, child: Text('Default')),
                DropdownMenuItem(value: 1.1, child: Text('Large')),
                DropdownMenuItem(value: 1.25, child: Text('Larger')),
                DropdownMenuItem(value: 1.4, child: Text('Extra large')),
              ],
            ),
          ),
        ],
      ),
    ],
  );

  Widget _backupSection(BuildContext context) => ListView(
    children: [
      const _SettingsSectionHeader(
        title: 'Backup & sync',
        description:
            'Connect GitHub, set its schedule, and manage local backups.',
      ),
      _SettingsGroup(
        children: [
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
          if (PlatformCapabilities.current.supportsPortableBackupDocuments)
            OutlinedButton.icon(
              onPressed: _saving ? null : _exportPortableBackup,
              icon: const Icon(Icons.save_alt_outlined),
              label: const Text('Export portable backup'),
            ),
          if (PlatformCapabilities.current.supportsPortableBackupDocuments &&
              _configuredOwner.isEmpty)
            OutlinedButton.icon(
              onPressed: _saving ? null : _restorePortableBackup,
              icon: const Icon(Icons.restore),
              label: const Text('Restore portable backup'),
            ),
        ],
      ),
      const SizedBox(height: 16),
      const _SettingsGroupLabel('GitHub connection'),
      _SettingsGroup(
        children: [
          TextField(
            controller: _token,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'GitHub personal access token',
            ),
          ),
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
            Text(
              _repositoryError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          TextField(
            controller: _owner,
            decoration: const InputDecoration(labelText: 'Repository owner'),
          ),
          TextField(
            controller: _repo,
            decoration: const InputDecoration(labelText: 'Repository name'),
          ),
          DropdownButtonFormField<int>(
            key: ValueKey(_syncIntervalMinutes),
            initialValue: _syncIntervalMinutes,
            decoration: InputDecoration(
              labelText:
                  PlatformCapabilities.current.supportsBestEffortInProcessSync
                  ? 'Best-effort sync while open'
                  : 'Background sync',
              helperText: syncScheduleDescription(PlatformCapabilities.current),
            ),
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
          if (_isChangingRepository) ...[
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
        ],
      ),
      const SizedBox(height: 16),
      const _SettingsGroupLabel('Troubleshooting'),
      _SettingsGroup(
        children: [
          SwitchListTile(
            value: _syncDiagnosticsEnabled,
            onChanged: _setSyncDiagnostics,
            secondary: const Icon(Icons.bug_report_outlined),
            title: const Text('Sync diagnostics'),
            subtitle: const Text('Show detailed stages and keep a sync log.'),
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
              'Check every remote note and apply deletions.',
            ),
            enabled: !_saving,
            onTap: _saving ? null : _runFullGitHubSync,
          ),
          if (_configuredOwner.isNotEmpty)
            OutlinedButton.icon(
              onPressed: _saving || _isChangingRepository
                  ? null
                  : () => _clearLocalCache(switching: false),
              icon: const Icon(Icons.delete_sweep_outlined),
              label: const Text('Clear local sync cache'),
            ),
        ],
      ),
      _saveButton(),
    ],
  );

  Widget _aiSection(BuildContext context) => ListView(
    children: [
      const _SettingsSectionHeader(
        title: 'AI summaries',
        description:
            'Configure the OpenAI-compatible service used to summarize notes.',
      ),
      _SettingsGroup(
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
      _saveButton(),
    ],
  );

  Widget _voiceSection(BuildContext context) => ListView(
    children: [
      const _SettingsSectionHeader(
        title: 'Voice',
        description:
            'Set the OpenAI models and credentials used for transcription.',
      ),
      _SettingsGroup(
        children: [
          const Text(
            'Live transcription, recovery uploads, and light cleanup use your OpenAI API key directly.',
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
      _saveButton(),
    ],
  );

  Widget _saveButton() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: FilledButton.icon(
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
  );
}

class _SettingsSectionHeader extends StatelessWidget {
  const _SettingsSectionHeader({
    required this.title,
    required this.description,
  });

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 4, 4, 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 6),
        Text(description, style: Theme.of(context).textTheme.bodyMedium),
      ],
    ),
  );
}

class _SettingsGroupLabel extends StatelessWidget {
  const _SettingsGroupLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
    child: Text(label, style: Theme.of(context).textTheme.titleSmall),
  );
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children
            .map(
              (child) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: child,
              ),
            )
            .toList(),
      ),
    ),
  );
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
