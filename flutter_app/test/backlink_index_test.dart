import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:specular/src/data/app_database.dart';
import 'package:specular/src/data/note_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'indexes wiki and Markdown backlinks across import, rename, and delete',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'specular-links-test-',
      );
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      final repository = NoteRepository(
        database,
        Directory('${root.path}/notes'),
      );
      addTearDown(() async {
        await database.close();
        await root.delete(recursive: true);
      });

      // Import the source before its targets, as happens during a remote sync.
      await repository.applyRemote(
        path: 'notes/source.md',
        sha: 'source-sha',
        raw: '''# Source

[[Target]]
[Target file](target.md)
''',
      );
      await repository.applyRemote(
        path: 'notes/target.md',
        sha: 'target-sha',
        raw: '# Target\n',
      );
      var target = await repository.findByPath('notes/target.md');
      expect(target, isNotNull);
      expect(await repository.watchBacklinks(target!).first, hasLength(2));

      target = await repository.rename(target, 'archive/target.md');
      final afterRename = await repository.watchBacklinks(target).first;
      expect(afterRename, hasLength(2));
      expect(afterRename.map((backlink) => backlink.sourceNoteTitle), [
        'Source',
        'Source',
      ]);
      expect(
        (await repository.findByPath('notes/source.md'))!.body,
        contains('[Target file](../archive/target.md)'),
      );

      await repository.delete(
        (await repository.findByPath('notes/source.md'))!,
      );
      expect(await repository.watchBacklinks(target).first, isEmpty);
    },
  );
}
