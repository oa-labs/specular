import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:specular/src/data/app_database.dart';
import 'package:specular/src/data/note_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('appends a new to-do to today\'s daily note', () async {
    final root = await Directory.systemTemp.createTemp('specular-todo-test-');
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(() async {
      await database.close();
      await root.delete(recursive: true);
    });
    final repository = NoteRepository(
      database,
      Directory('${root.path}/notes'),
    );

    final daily = await repository.appendToToday('- [ ] Buy milk');

    expect(daily.isDaily, isTrue);
    expect(daily.path, startsWith('daily/'));
    expect(daily.body, contains('- [ ] Buy milk'));
    expect(
      (await repository.watchNotes().first).where((note) => !note.isDaily),
      isEmpty,
    );
  });
}
