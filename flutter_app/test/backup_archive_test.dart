import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:specular/src/backup/backup_archive.dart';
import 'package:specular/src/data/app_database.dart';
import 'package:specular/src/data/note_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'portable backup round-trips Markdown, attachments, and pin state',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'specular-backup-test-',
      );
      final firstDatabase = AppDatabase.forTesting(NativeDatabase.memory());
      final first = NoteRepository(
        firstDatabase,
        Directory('${root.path}/first'),
      );
      final created = await first.create(
        title: 'Packing list',
        body: '- [ ] Passport',
      );
      await first.setPinned(created, true);
      final image = File('${root.path}/image.png');
      await image.writeAsBytes([137, 80, 78, 71]);
      await first.importImage((await first.get(created.id))!, image);
      final archive = File('${root.path}/backup.zip');
      await BackupArchiveService(first).exportTo(archive);

      final secondDatabase = AppDatabase.forTesting(NativeDatabase.memory());
      final second = NoteRepository(
        secondDatabase,
        Directory('${root.path}/second'),
      );
      final service = BackupArchiveService(second);
      final prepared = await service.prepareRestore(
        archive,
        Directory('${root.path}/staging'),
      );
      await service.restore(prepared);

      final restored = (await second.notesForBackup()).single;
      expect(restored.title, 'Packing list');
      expect(restored.isPinned, isTrue);
      expect(restored.body, contains('Passport'));
      expect(restored.rawMarkdown, contains('attachments/'));
      expect(
        await second.attachmentBytes(
          'attachments/${_attachmentName(restored.rawMarkdown)}',
        ),
        isNotNull,
      );

      await firstDatabase.close();
      await secondDatabase.close();
      await root.delete(recursive: true);
    },
  );

  test('invalid backup does not create notes', () async {
    final root = await Directory.systemTemp.createTemp('specular-backup-test-');
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final repository = NoteRepository(
      database,
      Directory('${root.path}/notes'),
    );
    final archive = File('${root.path}/invalid.zip')
      ..writeAsStringSync('not a zip');

    await expectLater(
      BackupArchiveService(
        repository,
      ).prepareRestore(archive, Directory('${root.path}/staging')),
      throwsA(isA<Object>()),
    );
    expect(await repository.hasLocalNotes(), isFalse);

    await database.close();
    await root.delete(recursive: true);
  });
}

String _attachmentName(String markdown) {
  final match = RegExp(r'attachments/([^\)]+)').firstMatch(markdown);
  return match!.group(1)!;
}
