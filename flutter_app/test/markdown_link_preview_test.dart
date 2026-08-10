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
}
