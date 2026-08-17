import 'dart:async';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../data/app_database.dart';
import '../data/note_repository.dart';
import '../ai/ai_summary_service.dart';
import '../domain/note.dart';
import '../sync/github_sync.dart';
import '../sync/github_auth.dart';
import '../voice/voice_service.dart';
import '../platform/widget_bridge.dart';
import '../platform/platform_capabilities.dart';
import '../sync/sync_scheduler.dart';
import 'screens.dart';

/// Material's compact/medium boundary. At this width a navigation rail leaves
/// enough room for the primary note content without turning a phone UI into a
/// stretched single column.
const tabletLayoutBreakpoint = 600.0;

/// Use labels in the app rail once there is room for both navigation and a
/// comfortably constrained reading column.
const expandedNavigationBreakpoint = 840.0;

bool usesWideLayout(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= tabletLayoutBreakpoint;

final appDatabaseProvider = Provider<AppDatabase>(
  (_) => throw UnimplementedError(),
);
final noteRepositoryProvider = Provider<NoteRepository>(
  (_) => throw UnimplementedError(),
);
final secureStorageProvider = Provider<FlutterSecureStorage>(
  (_) => throw UnimplementedError(),
);
final syncEngineProvider = Provider<GitHubSyncEngine>(
  (ref) => GitHubSyncEngine(
    ref.watch(noteRepositoryProvider),
    ref.watch(secureStorageProvider),
  ),
);
final gitHubAuthorizationProvider = Provider<GitHubAuthorizationService>(
  (ref) => GitHubAuthorizationService(ref.watch(secureStorageProvider)),
);
final syncControllerProvider = ChangeNotifierProvider<SyncController>(
  (ref) => SyncController(
    ref.watch(syncEngineProvider),
    ref.watch(secureStorageProvider),
    ref.watch(noteRepositoryProvider),
  ),
);
final voiceServiceProvider = Provider<VoiceService>(
  (ref) => VoiceService(ref.watch(secureStorageProvider)),
);
final aiSummaryServiceProvider = Provider<AiSummaryService>(
  (ref) => AiSummaryService(ref.watch(secureStorageProvider)),
);
final themeModeControllerProvider = ChangeNotifierProvider<ThemeModeController>(
  (_) => ThemeModeController(ThemeMode.light),
);
final textScaleControllerProvider = ChangeNotifierProvider<TextScaleController>(
  (_) => TextScaleController(defaultTextScale),
);
final notesProvider = StreamProvider<List<Note>>(
  (ref) => ref.watch(noteRepositoryProvider).watchNotes(),
);

/// Keeps the home tab selected while a route that replaces the home route is
/// open, such as saving an edited note and returning through its preview.
final homeSelectedViewProvider = StateProvider<NoteListView>(
  (_) => NoteListView.daily,
);

enum TodoFilter { open, done, all }

final todosProvider = StreamProvider.family<List<TodoItem>, TodoFilter>(
  (ref, filter) => ref
      .watch(noteRepositoryProvider)
      .watchTodos(includeCompleted: filter != TodoFilter.open)
      .map(
        (todos) => filter == TodoFilter.done
            ? todos.where((todo) => todo.isCompleted).toList()
            : todos,
      ),
);

const lastRouteStorageKey = 'last_route';
const themeModeStorageKey = 'theme_mode';
const textScaleStorageKey = 'text_scale';
const defaultTextScale = 1.0;
const onboardingCompletedStorageKey = 'onboarding_completed';
const backupPromptDismissedStorageKey = 'backup_prompt_dismissed';

enum BackupStatusKind { localOnly, pending, backedUp }

class BackupStatus {
  const BackupStatus({
    required this.kind,
    this.repository,
    this.lastSuccessfulSync,
  });

  final BackupStatusKind kind;
  final String? repository;
  final DateTime? lastSuccessfulSync;
}

Future<BackupStatus> readBackupStatus(
  FlutterSecureStorage storage,
  NoteRepository repository,
) async {
  final settings = await GitHubSettings.load(storage);
  if (settings == null) {
    return const BackupStatus(kind: BackupStatusKind.localOnly);
  }
  if (await repository.hasPendingSyncChanges()) {
    return BackupStatus(
      kind: BackupStatusKind.pending,
      repository: '${settings.owner}/${settings.repo}',
    );
  }
  final saved = await storage.read(key: lastSuccessfulGitHubSyncStorageKey);
  if (saved == null) {
    return BackupStatus(
      kind: BackupStatusKind.pending,
      repository: '${settings.owner}/${settings.repo}',
    );
  }
  return BackupStatus(
    kind: BackupStatusKind.backedUp,
    repository: '${settings.owner}/${settings.repo}',
    lastSuccessfulSync: DateTime.tryParse(saved),
  );
}

/// The current backup state is shared by home and settings so a completed
/// connection or sync updates both screens without waiting for a manual pull
/// to refresh home.
final backupStatusProvider = FutureProvider<BackupStatus>(
  (ref) => readBackupStatus(
    ref.watch(secureStorageProvider),
    ref.watch(noteRepositoryProvider),
  ),
);

class SyncUiState {
  const SyncUiState({
    this.isSyncing = false,
    this.isInitialSync = false,
    this.message = '',
    this.completed,
    this.total,
    this.itemLabel,
  });

  final bool isSyncing;
  final bool isInitialSync;
  final String message;
  final int? completed;
  final int? total;
  final String? itemLabel;
}

/// Gives foreground syncs one consistent visual state. Background work stays
/// intentionally quiet: Android may run it while there is no app to present.
class SyncController extends ChangeNotifier {
  SyncController(this._engine, this._storage, this._repository) {
    unawaited(_loadDiagnostics());
    unawaited(_refreshSharedSyncActivity());
    _activityPoll = Timer.periodic(
      const Duration(seconds: 1),
      (_) => unawaited(_refreshSharedSyncActivity()),
    );
  }

  final GitHubSyncEngine _engine;
  final FlutterSecureStorage _storage;
  final NoteRepository _repository;
  SyncUiState _state = const SyncUiState();
  var _activeSyncs = 0;
  var _sharedSyncActive = false;
  var _diagnosticsEnabled = false;
  late final Timer _activityPoll;

  SyncUiState get state => _state;

  Future<void> setDiagnosticsEnabled(bool enabled) async {
    _diagnosticsEnabled = enabled;
    await SyncDiagnostics.setEnabled(_storage, enabled);
    await _refreshSharedSyncActivity();
  }

  Future<void> _loadDiagnostics() async {
    try {
      _diagnosticsEnabled = await SyncDiagnostics.isEnabled(_storage);
      await _refreshSharedSyncActivity();
    } catch (_) {
      // Diagnostics default to off if secure storage is unavailable.
    }
  }

  Future<SyncResult> sync({bool forceFullRemoteScan = false}) async {
    if (await GitHubSettings.load(_storage) == null) {
      return _engine.sync(forceFullRemoteScan: forceFullRemoteScan);
    }
    final hasCompletedInitialSync =
        await _storage.read(key: initialSyncCompletedStorageKey) == 'true';
    // Existing installs predate this UI flag but already have a local library.
    // Only block the UI for a genuinely empty library's first sync.
    final isInitialSync =
        !hasCompletedInitialSync && !await _repository.hasLocalNotes();
    _activeSyncs++;
    _state = SyncUiState(
      isSyncing: true,
      isInitialSync: isInitialSync,
      message: isInitialSync ? 'Preparing your notes…' : 'Syncing with GitHub…',
    );
    notifyListeners();
    try {
      final result = await _engine.sync(
        onProgress: _updateProgress,
        forceFullRemoteScan: forceFullRemoteScan,
      );
      if (!hasCompletedInitialSync && result.message == 'Synced with GitHub') {
        await _storage.write(
          key: initialSyncCompletedStorageKey,
          value: 'true',
        );
      }
      if (result.isSuccess) {
        await _storage.write(
          key: lastSuccessfulGitHubSyncStorageKey,
          value: DateTime.now().toUtc().toIso8601String(),
        );
      }
      return result;
    } finally {
      _activeSyncs--;
      await _refreshSharedSyncActivity(notify: false);
      if (_activeSyncs == 0) {
        _state = _sharedSyncActive
            ? const SyncUiState(
                isSyncing: true,
                message: 'Syncing with GitHub…',
              )
            : const SyncUiState();
        notifyListeners();
      }
    }
  }

  void _updateProgress(SyncProgress progress) {
    if (!state.isSyncing) return;
    if (!_diagnosticsEnabled && SyncDiagnostics.isDetailedStage(progress)) {
      return;
    }
    _state = SyncUiState(
      isSyncing: true,
      isInitialSync: state.isInitialSync,
      message: progress.message,
      completed: progress.completed,
      total: progress.total,
      itemLabel: progress.itemLabel,
    );
    notifyListeners();
  }

  Future<void> _refreshSharedSyncActivity({bool notify = true}) async {
    final active = await _repository.isGitHubSyncActive();
    SyncProgress? sharedProgress;
    if (active) {
      try {
        sharedProgress = await SharedSyncProgress.load(_storage);
      } catch (_) {
        // A generic active state still communicates background work if secure
        // storage is briefly unavailable.
      }
    }
    if (!_diagnosticsEnabled &&
        sharedProgress != null &&
        SyncDiagnostics.isDetailedStage(sharedProgress)) {
      sharedProgress = null;
    }
    final next = active
        ? SyncUiState(
            isSyncing: true,
            message: sharedProgress?.message ?? 'Syncing with GitHub…',
            completed: sharedProgress?.completed,
            total: sharedProgress?.total,
            itemLabel: sharedProgress?.itemLabel,
          )
        : const SyncUiState();
    final changed =
        _sharedSyncActive != active ||
        (_activeSyncs == 0 &&
            (state.message != next.message ||
                state.completed != next.completed ||
                state.total != next.total ||
                state.itemLabel != next.itemLabel));
    _sharedSyncActive = active;
    // A foreground sync supplies detailed progress, so only replace the UI
    // state when the durable lease belongs to another isolate.
    if (_activeSyncs != 0) return;
    if (!changed) return;
    _state = next;
    if (notify) notifyListeners();
  }

  @override
  void dispose() {
    _activityPoll.cancel();
    super.dispose();
  }
}

ThemeMode themeModeFromStorage(String? value) =>
    value == 'dark' ? ThemeMode.dark : ThemeMode.light;

String themeModeStorageValue(ThemeMode mode) =>
    mode == ThemeMode.dark ? 'dark' : 'light';

double textScaleFromStorage(String? value) {
  final scale = double.tryParse(value ?? '');
  return scale == null ? defaultTextScale : scale.clamp(0.9, 1.4);
}

class ThemeModeController extends ChangeNotifier {
  ThemeModeController(this._themeMode);

  ThemeMode _themeMode;

  ThemeMode get themeMode => _themeMode;

  void setThemeMode(ThemeMode mode) {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
  }
}

class TextScaleController extends ChangeNotifier {
  TextScaleController(this._textScale);

  double _textScale;

  double get textScale => _textScale;

  void setTextScale(double scale) {
    final next = scale.clamp(0.9, 1.4);
    if (_textScale == next) return;
    _textScale = next;
    notifyListeners();
  }
}

/// Explicit launch destinations, such as an Android widget tap, take
/// precedence over the page from the previous app session.
String initialLocationFor({
  required String platformRoute,
  required String? savedRoute,
}) => platformRoute != Navigator.defaultRouteName
    ? platformRoute
    : savedRoute ?? Navigator.defaultRouteName;

class SpecularApp extends ConsumerStatefulWidget {
  const SpecularApp({
    super.key,
    this.initialLocation = Navigator.defaultRouteName,
  });

  final String initialLocation;

  @override
  ConsumerState<SpecularApp> createState() => _SpecularAppState();
}

class _SpecularAppState extends ConsumerState<SpecularApp> {
  late final GoRouter _router;
  late final _lifecycleObserver = _AppLifecycleObserver(_onLifecycle);

  @override
  void initState() {
    super.initState();
    _router = GoRouter(
      initialLocation: widget.initialLocation,
      routes: [
        GoRoute(path: '/', builder: (_, _) => const NoteListScreen()),
        GoRoute(
          path: '/search',
          builder: (_, _) => const _BackToHome(child: SearchScreen()),
        ),
        GoRoute(
          path: '/todos',
          builder: (_, _) => const _BackToHome(child: TodoScreen()),
        ),
        GoRoute(
          path: '/settings',
          builder: (_, _) => const _BackToHome(child: SettingsScreen()),
        ),
        GoRoute(
          path: '/voice',
          builder: (_, state) => _BackToHome(
            child: VoiceCaptureScreen(
              noteId: state.uri.queryParameters['note'],
            ),
          ),
        ),
        GoRoute(
          path: '/editor/new',
          builder: (_, state) {
            final dailyDate = state.uri.queryParameters['daily'];
            final isDailyDate =
                dailyDate != null &&
                RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(dailyDate);
            return _BackToHome(
              child: EditorScreen(dailyDate: isDailyDate ? dailyDate : null),
            );
          },
        ),
        GoRoute(
          path: '/editor/todo',
          builder: (_, _) =>
              const _BackToHome(child: EditorScreen(newTodo: true)),
        ),
        GoRoute(
          path: '/note/:id',
          builder: (_, state) => _BackToHome(
            child: NoteDetailScreen(id: state.pathParameters['id']!),
          ),
        ),
        GoRoute(
          path: '/editor/:id',
          builder: (_, state) => _BackToHome(
            child: EditorScreen(
              id: state.pathParameters['id'],
              startVoice: state.uri.queryParameters['voice'] == 'true',
            ),
          ),
        ),
      ],
    );
    _router.routerDelegate.addListener(_saveCurrentRoute);
    WidgetBridge.setNavigationHandler(_router.go);
    WidgetsBinding.instance.addObserver(_lifecycleObserver);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      SyncScheduler.registerForegroundSync(_syncWhenConfigured);
      unawaited(_syncWhenConfigured());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(_lifecycleObserver);
    _router.routerDelegate.removeListener(_saveCurrentRoute);
    _router.dispose();
    super.dispose();
  }

  void _saveCurrentRoute() {
    final location = _router.routerDelegate.currentConfiguration.uri.toString();
    unawaited(
      ref
          .read(secureStorageProvider)
          .write(key: lastRouteStorageKey, value: location),
    );
  }

  Future<void> _syncWhenConfigured() async {
    if (!PlatformCapabilities.current.isDesktop) return;
    if (await GitHubSettings.load(ref.read(secureStorageProvider)) == null) {
      return;
    }
    await ref.read(syncControllerProvider).sync();
  }

  void _onLifecycle(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(SyncScheduler.syncOnAppResume());
    }
  }

  @override
  Widget build(BuildContext context) {
    const amber = Color(0xffd97706);
    final themeMode = ref.watch(themeModeControllerProvider).themeMode;
    final textScale = ref.watch(textScaleControllerProvider).textScale;
    final syncState = ref.watch(syncControllerProvider).state;
    return MaterialApp.router(
      title: 'Specular',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        AppFlowyEditorLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: amber,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: amber,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: themeMode,
      routerConfig: _router,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: _AdaptiveAppShell(
          router: _router,
          child: Stack(
            children: [
              child ?? const SizedBox.shrink(),
              if (syncState.isSyncing && syncState.isInitialSync)
                _InitialSyncOverlay(state: syncState),
              if (syncState.isSyncing && !syncState.isInitialSync)
                _SyncProgressSnackbar(state: syncState),
            ],
          ),
        ),
      ),
    );
  }
}

class _AppLifecycleObserver with WidgetsBindingObserver {
  _AppLifecycleObserver(this.onChanged);

  final ValueChanged<AppLifecycleState> onChanged;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => onChanged(state);

  @override
  bool operator ==(Object other) =>
      other is _AppLifecycleObserver && other.onChanged == onChanged;

  @override
  int get hashCode => onChanged.hashCode;
}

/// Keeps the compact phone UI below 600dp and provides persistent navigation
/// for tablets and desktops. Desktop-only menu and shortcut integrations stay
/// desktop-only; Android tablets receive the same adaptive visual structure.
class _AdaptiveAppShell extends StatelessWidget {
  const _AdaptiveAppShell({required this.router, required this.child});

  final GoRouter router;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final adaptiveChild = LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < tabletLayoutBreakpoint) return child;
        final extended = constraints.maxWidth >= expandedNavigationBreakpoint;
        return Row(
          children: [
            NavigationRail(
              extended: extended,
              selectedIndex: _selectedIndex(router),
              labelType: extended
                  ? NavigationRailLabelType.none
                  : NavigationRailLabelType.all,
              leading: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: extended
                    ? FilledButton.icon(
                        onPressed: () => router.go('/editor/new'),
                        icon: const Icon(Icons.add),
                        label: const Text('New note'),
                      )
                    : Semantics(
                        button: true,
                        label: 'New note',
                        child: SizedBox.square(
                          dimension: 48,
                          child: FilledButton(
                            onPressed: () => router.go('/editor/new'),
                            style: FilledButton.styleFrom(
                              padding: EdgeInsets.zero,
                              shape: const CircleBorder(),
                            ),
                            child: const Center(child: Icon(Icons.add)),
                          ),
                        ),
                      ),
              ),
              destinations: const [
                NavigationRailDestination(
                  icon: Icon(Icons.today_outlined),
                  selectedIcon: Icon(Icons.today),
                  label: Text('Daily'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.checklist_outlined),
                  selectedIcon: Icon(Icons.checklist),
                  label: Text('To-dos'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.search),
                  label: Text('Search'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.settings_outlined),
                  selectedIcon: Icon(Icons.settings),
                  label: Text('Settings'),
                ),
              ],
              onDestinationSelected: (index) => router.go(switch (index) {
                0 => '/',
                1 => '/todos',
                2 => '/search',
                _ => '/settings',
              }),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: child),
          ],
        );
      },
    );
    if (!PlatformCapabilities.current.isDesktop) return adaptiveChild;
    final desktopChild = CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyN, meta: true): () =>
            router.go('/editor/new'),
        const SingleActivator(LogicalKeyboardKey.keyT, meta: true): () =>
            router.go('/editor/todo'),
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true): () =>
            router.go('/search'),
        const SingleActivator(LogicalKeyboardKey.keyR, meta: true): () =>
            _sync(),
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (router.canPop()) router.pop();
        },
      },
      child: Focus(autofocus: true, child: adaptiveChild),
    );
    return PlatformMenuBar(
      menus: [
        if (PlatformProvidedMenuItem.hasMenu(PlatformProvidedMenuItemType.quit))
          PlatformMenu(
            label: 'Specular',
            menus: const [
              // Lets macOS provide its standard Quit Specular (⌘Q) command.
              PlatformProvidedMenuItem(type: .quit),
            ],
          ),
        PlatformMenu(
          label: 'File',
          menus: [
            PlatformMenuItem(
              label: 'New Note',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyN,
                meta: true,
              ),
              onSelected: () => router.go('/editor/new'),
            ),
            PlatformMenuItem(
              label: 'New To-do',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyT,
                meta: true,
              ),
              onSelected: () => router.go('/editor/todo'),
            ),
          ],
        ),
        PlatformMenu(
          label: 'Navigate',
          menus: [
            PlatformMenuItem(
              label: 'Search Notes',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyF,
                meta: true,
              ),
              onSelected: () => router.go('/search'),
            ),
            PlatformMenuItem(
              label: 'To-dos',
              onSelected: () => router.go('/todos'),
            ),
            PlatformMenuItem(
              label: 'Settings',
              onSelected: () => router.go('/settings'),
            ),
          ],
        ),
        PlatformMenu(
          label: 'Sync',
          menus: [
            PlatformMenuItem(
              label: 'Refresh from GitHub',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyR,
                meta: true,
              ),
              onSelected: _sync,
            ),
          ],
        ),
      ],
      child: desktopChild,
    );
  }

  int _selectedIndex(GoRouter router) {
    final path = router.routerDelegate.currentConfiguration.uri.path;
    if (path.startsWith('/todos')) return 1;
    if (path.startsWith('/search')) return 2;
    if (path.startsWith('/settings')) return 3;
    return 0;
  }

  void _sync() {
    // The home screen retains its pull-to-refresh control. Cmd-R is provided
    // as a desktop convenience and uses the same foreground engine.
    final context = router.routerDelegate.navigatorKey.currentContext;
    if (context == null) return;
    final container = ProviderScope.containerOf(context, listen: false);
    unawaited(container.read(syncControllerProvider).sync());
  }
}

/// A persistent, snackbar-shaped sync status. Unlike Scaffold snackbars it is
/// not replaced by navigation or by a screen's own confirmation messages.
class _SyncProgressSnackbar extends StatelessWidget {
  const _SyncProgressSnackbar({required this.state});

  final SyncUiState state;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final total = state.total;
    final completed = state.completed;
    final hasProgress = total != null && total > 0 && completed != null;
    final progress = hasProgress ? (completed / total).clamp(0.0, 1.0) : null;
    final text = hasProgress
        ? switch (state.itemLabel) {
            'notes' => 'Checking $completed of $total notes',
            'attachments' => 'Checking $completed of $total attachments',
            'changes' => 'Uploading $completed of $total changes',
            _ => '$completed of $total complete',
          }
        : state.message.isEmpty
        ? 'Syncing with GitHub…'
        : state.message;
    return Positioned(
      left: 12,
      right: 12,
      bottom: 12,
      child: SafeArea(
        top: false,
        child: Semantics(
          liveRegion: true,
          label: text,
          child: Material(
            color: colors.inverseSurface,
            elevation: 6,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colors.inversePrimary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          text,
                          style: TextStyle(color: colors.onInverseSurface),
                        ),
                      ),
                    ],
                  ),
                  if (progress != null) ...[
                    const SizedBox(height: 10),
                    LinearProgressIndicator(
                      value: progress,
                      color: colors.inversePrimary,
                      backgroundColor: colors.onInverseSurface.withValues(
                        alpha: .24,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SpecularWordmark extends StatefulWidget {
  const SpecularWordmark({super.key, required this.isSyncing});

  final bool isSyncing;

  @override
  State<SpecularWordmark> createState() => _SpecularWordmarkState();
}

class _SpecularWordmarkState extends State<SpecularWordmark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1450),
  );

  @override
  void initState() {
    super.initState();
    if (widget.isSyncing) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant SpecularWordmark oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSyncing && !oldWidget.isSyncing) {
      _controller.repeat();
    } else if (!widget.isSyncing && oldWidget.isSyncing) {
      _controller
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.titleLarge;
    final base = Text('Specular', style: style);
    if (!widget.isSyncing) return base;
    final highlight = Theme.of(context).colorScheme.primary;
    return Semantics(
      label: 'Specular, syncing',
      liveRegion: true,
      child: AnimatedBuilder(
        animation: _controller,
        child: base,
        builder: (context, child) {
          final sweep = -2 + _controller.value * 4;
          return ShaderMask(
            blendMode: BlendMode.srcATop,
            shaderCallback: (bounds) => LinearGradient(
              begin: Alignment(sweep, 0),
              end: Alignment(sweep + 1, 0),
              colors: [
                Colors.transparent,
                highlight.withValues(alpha: .9),
                Colors.transparent,
              ],
              stops: const [0, .5, 1],
            ).createShader(bounds),
            child: child,
          );
        },
      ),
    );
  }
}

class _InitialSyncOverlay extends StatelessWidget {
  const _InitialSyncOverlay({required this.state});

  final SyncUiState state;

  @override
  Widget build(BuildContext context) {
    final progress = state.total == null || state.total == 0
        ? null
        : state.completed! / state.total!;
    final detail = state.total == null
        ? null
        : '${state.completed ?? 0} of ${state.total}';
    return Material(
      color: Theme.of(context).colorScheme.scrim.withValues(alpha: .52),
      child: Center(
        child: Semantics(
          liveRegion: true,
          label: 'Initial sync in progress. ${state.message}',
          child: Container(
            width: 300,
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.auto_awesome,
                  color: Theme.of(context).colorScheme.primary,
                  size: 32,
                ),
                const SizedBox(height: 16),
                Text(
                  'Setting up Specular',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(state.message, textAlign: TextAlign.center),
                const SizedBox(height: 20),
                LinearProgressIndicator(value: progress),
                if (detail != null) ...[
                  const SizedBox(height: 8),
                  Text(detail, style: Theme.of(context).textTheme.labelMedium),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Secondary screens opened directly by the Android widget have no home route
/// beneath them. Fall back to home only in that case; otherwise preserve the
/// navigation history of the page that opened this screen.
class _BackToHome extends StatelessWidget {
  const _BackToHome({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final canPop = GoRouter.of(context).canPop();
    return PopScope(
      canPop: canPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) context.go('/');
      },
      child: child,
    );
  }
}
