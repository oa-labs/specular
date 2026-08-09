import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
final notesProvider = StreamProvider<List<Note>>(
  (ref) => ref.watch(noteRepositoryProvider).watchNotes(),
);
final todosProvider = StreamProvider<List<TodoItem>>(
  (ref) => ref.watch(noteRepositoryProvider).watchTodos(),
);

class SpecularApp extends ConsumerWidget {
  const SpecularApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = GoRouter(
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
    WidgetBridge.setNavigationHandler(router.go);
    const amber = Color(0xffd97706);
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
      routerConfig: router,
    );
  }
}

/// Secondary screens can be opened directly by the Android widget, leaving no
/// home route in the navigator stack. A system back gesture must still return
/// the user to the app's home screen rather than closing the app or exposing a
/// stale route beneath it.
class _BackToHome extends StatelessWidget {
  const _BackToHome({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) context.go('/');
    },
    child: child,
  );
}
