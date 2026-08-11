import 'dart:async';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
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
import '../voice/voice_service.dart';
import '../platform/widget_bridge.dart';
import 'screens.dart';

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
final syncControllerProvider = ChangeNotifierProvider<SyncController>(
  (ref) => SyncController(
    ref.watch(syncEngineProvider),
    ref.watch(secureStorageProvider),
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
final notesProvider = StreamProvider<List<Note>>(
  (ref) => ref.watch(noteRepositoryProvider).watchNotes(),
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

class SyncUiState {
  const SyncUiState({
    this.isSyncing = false,
    this.isInitialSync = false,
    this.message = '',
    this.completed,
    this.total,
  });

  final bool isSyncing;
  final bool isInitialSync;
  final String message;
  final int? completed;
  final int? total;
}

/// Gives foreground syncs one consistent visual state. Background work stays
/// intentionally quiet: Android may run it while there is no app to present.
class SyncController extends ChangeNotifier {
  SyncController(this._engine, this._storage);

  final GitHubSyncEngine _engine;
  final FlutterSecureStorage _storage;
  SyncUiState _state = const SyncUiState();
  var _activeSyncs = 0;

  SyncUiState get state => _state;

  Future<SyncResult> sync() async {
    if (await GitHubSettings.load(_storage) == null) {
      return _engine.sync();
    }
    final isInitialSync =
        await _storage.read(key: initialSyncCompletedStorageKey) != 'true';
    _activeSyncs++;
    _state = SyncUiState(
      isSyncing: true,
      isInitialSync: isInitialSync,
      message: isInitialSync ? 'Preparing your notes…' : 'Syncing with GitHub…',
    );
    notifyListeners();
    try {
      final result = await _engine.sync(onProgress: _updateProgress);
      if (isInitialSync && result.message == 'Synced with GitHub') {
        await _storage.write(
          key: initialSyncCompletedStorageKey,
          value: 'true',
        );
      }
      return result;
    } finally {
      _activeSyncs--;
      if (_activeSyncs == 0) {
        _state = const SyncUiState();
        notifyListeners();
      }
    }
  }

  void _updateProgress(SyncProgress progress) {
    if (!state.isSyncing) return;
    _state = SyncUiState(
      isSyncing: true,
      isInitialSync: state.isInitialSync,
      message: progress.message,
      completed: progress.completed,
      total: progress.total,
    );
    notifyListeners();
  }
}

ThemeMode themeModeFromStorage(String? value) =>
    value == 'dark' ? ThemeMode.dark : ThemeMode.light;

String themeModeStorageValue(ThemeMode mode) =>
    mode == ThemeMode.dark ? 'dark' : 'light';

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
  }

  @override
  void dispose() {
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

  @override
  Widget build(BuildContext context) {
    const amber = Color(0xffd97706);
    final themeMode = ref.watch(themeModeControllerProvider).themeMode;
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
      builder: (context, child) => Stack(
        children: [
          child ?? const SizedBox.shrink(),
          if (syncState.isSyncing && syncState.isInitialSync)
            _InitialSyncOverlay(state: syncState),
        ],
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
