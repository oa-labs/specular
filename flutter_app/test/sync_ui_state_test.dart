import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:specular/src/domain/note.dart';
import 'package:specular/src/ui/screens.dart';
import 'package:specular/src/ui/specular_app.dart';

void main() {
  const firstSync = SyncUiState(isSyncing: true, isInitialSync: true);
  const laterSync = SyncUiState(isSyncing: true, isInitialSync: false);
  const idle = SyncUiState();

  group('sync chrome gating', () {
    test('never uses a blocking overlay once local notes exist', () {
      for (final sync in [firstSync, laterSync]) {
        expect(
          syncBlocksHomeUi(sync, hasLocalNotes: true),
          isFalse,
        );
        expect(
          syncHomeProgressKind(sync, hasLocalNotes: true),
          SyncHomeProgressKind.snackbar,
        );
      }
    });

    test('first sync without notes stays non-blocking', () {
      expect(syncBlocksHomeUi(firstSync, hasLocalNotes: false), isFalse);
      expect(
        syncHomeProgressKind(firstSync, hasLocalNotes: false),
        SyncHomeProgressKind.snackbar,
      );
      expect(syncShowsProgressSnackbar(firstSync, hasLocalNotes: false), isTrue);
    });

    test('foreground, background, and pull-to-refresh stay snackbar-only', () {
      expect(
        syncHomeProgressKind(laterSync, hasLocalNotes: true),
        SyncHomeProgressKind.snackbar,
      );
      expect(
        syncHomeProgressKind(laterSync, hasLocalNotes: false),
        SyncHomeProgressKind.snackbar,
      );
      expect(syncHomeProgressKind(idle, hasLocalNotes: true), SyncHomeProgressKind.none);
      expect(syncShowsProgressSnackbar(idle, hasLocalNotes: true), isFalse);
    });

    test('no sync combination selects a blocking overlay', () {
      for (final isSyncing in [true, false]) {
        for (final isInitialSync in [true, false]) {
          for (final hasLocalNotes in [true, false]) {
            expect(
              syncHomeProgressKind(
                SyncUiState(
                  isSyncing: isSyncing,
                  isInitialSync: isInitialSync,
                ),
                hasLocalNotes: hasLocalNotes,
              ),
              isNot(SyncHomeProgressKind.blockingOverlay),
            );
          }
        }
      }
    });

    test('copyWith can drop isInitialSync when notes arrive mid-pull', () {
      expect(
        firstSync.copyWith(isInitialSync: false).isInitialSync,
        isFalse,
      );
    });

    test('historic isInitialSync flag cannot cover a populated library', () {
      expect(
        syncBlocksHomeUi(
          const SyncUiState(
            isSyncing: true,
            isInitialSync: true,
            message: 'Checking your notes…',
            completed: 1,
            total: 40,
            itemLabel: 'notes',
          ),
          hasLocalNotes: true,
        ),
        isFalse,
      );
    });
  });

  group('loading wipe gating', () {
    const previous = AsyncData<List<String>>(['kept']);

    test('first load with no prior data may show a spinner', () {
      expect(asyncValueWipesContent(const AsyncLoading<List<String>>()), isTrue);
      expect(
        shouldShowNotesLoadingSpinner(
          notes: const AsyncLoading<List<Note>>(),
        ),
        isTrue,
      );
    });

    test('reload after invalidate keeps prior notes on every home view', () {
      final reload = const AsyncLoading<List<String>>().copyWithPrevious(
        previous,
      );
      expect(reload.isLoading, isTrue);
      expect(reload.hasValue, isTrue);
      expect(asyncValueWipesContent(reload), isFalse);

      final notesReload = const AsyncLoading<List<Note>>().copyWithPrevious(
        const AsyncData<List<Note>>([]),
      );
      for (final _ in NoteListView.values) {
        expect(
          shouldShowNotesLoadingSpinner(notes: notesReload),
          isFalse,
        );
      }
    });

    test('refresh with previous todos does not wipe the list', () {
      final refresh = const AsyncLoading<List<String>>().copyWithPrevious(
        previous,
        isRefresh: true,
      );
      expect(asyncValueWipesContent(refresh), isFalse);
    });

    test('unloaded preferences still gate the All / Meetings / People shell', () {
      expect(
        shouldShowNotesLoadingSpinner(
          notes: const AsyncData<List<Note>>([]),
          preferencesLoaded: false,
        ),
        isTrue,
      );
      expect(
        shouldShowNotesLoadingSpinner(
          notes: const AsyncData<List<Note>>([]),
          preferencesLoaded: true,
        ),
        isFalse,
      );
    });

    test('search keeps prior hits while a replacement stream is waiting', () {
      expect(
        shouldShowSearchLoadingSpinner(
          isWaiting: true,
          hasPreviousResults: false,
        ),
        isTrue,
      );
      expect(
        shouldShowSearchLoadingSpinner(
          isWaiting: true,
          hasPreviousResults: true,
        ),
        isFalse,
      );
      expect(
        shouldShowSearchLoadingSpinner(
          isWaiting: false,
          hasPreviousResults: false,
        ),
        isFalse,
      );
    });
  });

  group('empty library copy', () {
    test('shows a lightweight importing state while sync fills an empty library', () {
      for (final view in [
        NoteListView.all,
        NoteListView.meetings,
        NoteListView.people,
      ]) {
        expect(
          emptyNotesLibraryMessage(
            view: view,
            hasAnyNotes: false,
            isSearching: false,
            isSyncing: true,
          ),
          'Importing notes from GitHub…',
        );
      }
    });

    test('does not hide a populated view behind importing copy', () {
      expect(
        emptyNotesLibraryMessage(
          view: NoteListView.meetings,
          hasAnyNotes: true,
          isSearching: false,
          isSyncing: true,
        ),
        'No meetings yet.',
      );
      expect(
        emptyNotesLibraryMessage(
          view: NoteListView.people,
          hasAnyNotes: true,
          isSearching: false,
          isSyncing: false,
        ),
        'No people yet.',
      );
    });

    test('keeps search-empty and idle-empty copy', () {
      expect(
        emptyNotesLibraryMessage(
          view: NoteListView.all,
          hasAnyNotes: true,
          isSearching: true,
          isSyncing: true,
        ),
        'No matching notes.',
      );
      expect(
        emptyNotesLibraryMessage(
          view: NoteListView.all,
          hasAnyNotes: false,
          isSearching: false,
          isSyncing: false,
        ),
        'No notes yet. Open Daily to start today\'s note.',
      );
    });
  });
}
