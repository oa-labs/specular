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
import '../ai/ai_snippet_service.dart';
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
final voiceServiceProvider = Provider<VoiceService>(
  (ref) => VoiceService(ref.watch(secureStorageProvider)),
);
final aiSnippetServiceProvider = Provider<AiSnippetService>(
  (ref) => AiSnippetService(ref.watch(secureStorageProvider)),
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
          builder: (_, _) => const _BackToHome(child: VoiceCaptureScreen()),
        ),
        GoRoute(
          path: '/editor/new',
          builder: (_, _) => const _BackToHome(child: EditorScreen()),
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
          builder: (_, state) =>
              _BackToHome(child: EditorScreen(id: state.pathParameters['id'])),
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
