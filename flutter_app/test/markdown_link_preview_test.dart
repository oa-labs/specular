import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:specular/src/data/app_database.dart';
import 'package:specular/src/data/note_repository.dart';
import 'package:specular/src/ui/screens.dart';
import 'package:specular/src/ui/specular_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('opens a note image in a pinch-to-zoom viewer', (tester) async {
    late Directory root;
    late AppDatabase database;
    late NoteRepository repository;
    late String noteId;

    await tester.runAsync(() async {
      root = await Directory.systemTemp.createTemp('specular-image-test-');
      database = AppDatabase.forTesting(NativeDatabase.memory());
      repository = NoteRepository(database, Directory('${root.path}/notes'));
      await repository.applyRemote(
        path: 'notes/photo.md',
        sha: 'note-sha',
        raw: '# Photo\n\n![](attachments/photo.png)\n',
      );
      await repository.applyRemoteAttachment(
        path: 'attachments/photo.png',
        sha: 'image-sha',
        bytes: await File(
          'android/app/src/main/res/mipmap-mdpi/ic_launcher.png',
        ).readAsBytes(),
      );
      expect(
        await repository.resolveAttachment(
          'notes/photo.md',
          'attachments/photo.png',
        ),
        isNotNull,
      );
      noteId = (await repository.findByPath('notes/photo.md'))!.id;
    });
    addTearDown(() async {
      await database.close();
      await root.delete(recursive: true);
    });

    final router = GoRouter(
      initialLocation: '/note/${Uri.encodeComponent(noteId)}',
      routes: [
        GoRoute(
          path: '/note/:id',
          builder: (_, state) =>
              NoteDetailScreen(id: state.pathParameters['id']!),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [noteRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();

    expect(find.text('Photo'), findsOneWidget);
    expect(find.byType(FutureBuilder<File?>), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('open-image-preview')));
    await tester.pumpAndSettle();

    expect(find.text('Image'), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);

    // Drift schedules stream cleanup on the next event-loop turn.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('opens a relative Markdown link from the note preview', (
    tester,
  ) async {
    late Directory root;
    late AppDatabase database;
    late NoteRepository repository;
    late String dailyId;

    await tester.runAsync(() async {
      root = await Directory.systemTemp.createTemp('specular-link-test-');
      database = AppDatabase.forTesting(NativeDatabase.memory());
      repository = NoteRepository(database, Directory('${root.path}/notes'));
      await repository.applyRemote(
        path: 'daily/2026-08-09.md',
        sha: 'daily-sha',
        raw: '''# Daily note

- [New Website Design Review - July 15, 2026](../meetings/NewWebsiteDesignReviewJuly15,2026.md)
''',
      );
      await repository.applyRemote(
        path: 'meetings/NewWebsiteDesignReviewJuly15,2026.md',
        sha: 'meeting-sha',
        raw: '# Website design review\n',
      );
      final daily = await repository.findByPath('daily/2026-08-09.md');
      final meeting = await repository.findByPath(
        'meetings/NewWebsiteDesignReviewJuly15,2026.md',
      );
      expect(daily, isNotNull);
      expect(meeting, isNotNull);
      dailyId = daily!.id;
    });
    addTearDown(() async {
      await database.close();
      await root.delete(recursive: true);
    });

    final router = GoRouter(
      initialLocation: '/note/${Uri.encodeComponent(dailyId)}',
      routes: [
        GoRoute(
          path: '/note/:id',
          builder: (_, state) =>
              NoteDetailScreen(id: state.pathParameters['id']!),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [noteRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('New Website Design Review - July 15, 2026'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Website design review'), findsOneWidget);

    // Drift schedules stream cleanup on the next event-loop turn.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('opens a Markdown link from the daily preview', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    late Directory root;
    late AppDatabase database;
    late NoteRepository repository;

    await tester.runAsync(() async {
      root = await Directory.systemTemp.createTemp('specular-daily-link-test-');
      database = AppDatabase.forTesting(NativeDatabase.memory());
      repository = NoteRepository(database, Directory('${root.path}/notes'));
      final today = formatDailyDate(DateTime.now());
      await repository.applyRemote(
        path: 'daily/$today.md',
        sha: 'daily-sha',
        raw: '[Open design review](../meetings/design-review.md)\n',
      );
      await repository.applyRemote(
        path: 'meetings/design-review.md',
        sha: 'meeting-sha',
        raw: '# Design review\n',
      );
    });
    addTearDown(() async {
      await database.close();
      await root.delete(recursive: true);
    });

    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, _) => const DailyNotesScreen()),
        GoRoute(
          path: '/note/:id',
          builder: (_, state) =>
              NoteDetailScreen(id: state.pathParameters['id']!),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [noteRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('Open design review'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Design review'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('makes macOS note-preview text selectable', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    late Directory root;
    late AppDatabase database;
    late NoteRepository repository;
    late String noteId;

    await tester.runAsync(() async {
      root = await Directory.systemTemp.createTemp('specular-selection-test-');
      database = AppDatabase.forTesting(NativeDatabase.memory());
      repository = NoteRepository(database, Directory('${root.path}/notes'));
      await repository.applyRemote(
        path: 'notes/selectable.md',
        sha: 'note-sha',
        raw: '# Selectable note\n\nCopy this preview text.\n',
      );
      noteId = (await repository.findByPath('notes/selectable.md'))!.id;
    });
    addTearDown(() async {
      await database.close();
      await root.delete(recursive: true);
    });

    final router = GoRouter(
      initialLocation: '/note/${Uri.encodeComponent(noteId)}',
      routes: [
        GoRoute(
          path: '/note/:id',
          builder: (_, state) =>
              NoteDetailScreen(id: state.pathParameters['id']!),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [noteRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    if (Platform.isMacOS) {
      expect(find.byType(SelectableText), findsWidgets);
      expect(
        tester
            .getTopLeft(find.byKey(const ValueKey('note-preview-markdown')))
            .dx,
        closeTo(80.8, 0.01),
      );
    } else {
      expect(find.byType(SelectableText), findsNothing);
    }

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
