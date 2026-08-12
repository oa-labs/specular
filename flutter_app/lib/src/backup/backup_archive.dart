import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import '../data/note_repository.dart';

const backupManifestName = 'specular-backup.json';
const _notesDirectory = 'notes/';

class BackupArchiveException implements Exception {
  const BackupArchiveException(this.message);
  final String message;
  @override
  String toString() => message;
}

class BackupArchiveService {
  BackupArchiveService(this._repository);
  final NoteRepository _repository;

  Future<void> exportTo(File destination) async {
    final notes = await _repository.notesForBackup();
    final archive = Archive();
    final manifest = <String, Object>{
      'formatVersion': 1,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'notes': [
        for (final note in notes)
          {
            'id': note.id,
            'path': note.path,
            'isPinned': note.isPinned,
            'updatedAt': note.updatedAt.toUtc().toIso8601String(),
          },
      ],
    };
    final manifestBytes = utf8.encode(jsonEncode(manifest));
    archive.addFile(
      ArchiveFile(backupManifestName, manifestBytes.length, manifestBytes),
    );
    await for (final entity in _repository.notesRoot.list(recursive: true)) {
      if (entity is! File) continue;
      final relative = p
          .relative(entity.path, from: _repository.notesRoot.path)
          .replaceAll('\\', '/');
      if (relative.startsWith('.editor-staging/')) continue;
      final bytes = await entity.readAsBytes();
      archive.addFile(
        ArchiveFile('$_notesDirectory$relative', bytes.length, bytes),
      );
    }
    final bytes = ZipEncoder().encode(archive);
    await destination.parent.create(recursive: true);
    await destination.writeAsBytes(bytes, flush: true);
  }

  /// Validate and extract an archive before any local-library mutation.
  Future<PreparedBackup> prepareRestore(
    File archiveFile,
    Directory staging,
  ) async {
    if (!await archiveFile.exists()) {
      throw const BackupArchiveException(
        'The selected backup is no longer available.',
      );
    }
    final archive = ZipDecoder().decodeBytes(await archiveFile.readAsBytes());
    ArchiveFile? manifestFile;
    final names = <String>{};
    for (final file in archive.files) {
      final name = file.name.replaceAll('\\', '/');
      if (!_safeArchivePath(name) || !names.add(name)) {
        throw const BackupArchiveException(
          'The backup contains an unsafe or duplicate path.',
        );
      }
      if (name == backupManifestName) manifestFile = file;
    }
    if (manifestFile == null || !manifestFile.isFile) {
      throw const BackupArchiveException(
        'This is not a Specular backup archive.',
      );
    }
    final manifest = _decodeManifest(manifestFile.content);
    final notes = manifest['notes'];
    if (notes is! List) {
      throw const BackupArchiveException('The backup note list is invalid.');
    }
    final pinned = <String, bool>{};
    final notePaths = <String>{};
    for (final entry in notes) {
      if (entry is! Map) {
        throw const BackupArchiveException('The backup note list is invalid.');
      }
      final path = entry['path']?.toString() ?? '';
      final id = entry['id']?.toString() ?? '';
      if (id.isEmpty || !_safeLibraryPath(path) || !notePaths.add(path)) {
        throw const BackupArchiveException(
          'The backup contains an invalid note.',
        );
      }
      if (!names.contains('$_notesDirectory$path')) {
        throw BackupArchiveException('The backup is missing $path.');
      }
      pinned[path] = entry['isPinned'] == true;
    }
    await staging.create(recursive: true);
    for (final file in archive.files) {
      if (!file.isFile || !file.name.startsWith(_notesDirectory)) continue;
      final relative = file.name.substring(_notesDirectory.length);
      if (!_safeLibraryPath(relative)) {
        throw const BackupArchiveException(
          'The backup contains an unsafe file path.',
        );
      }
      final output = File(p.join(staging.path, relative));
      await output.parent.create(recursive: true);
      final content = file.content;
      await output.writeAsBytes(content, flush: true);
    }
    return PreparedBackup(staging, pinned);
  }

  Future<void> restore(PreparedBackup backup) =>
      _repository.restorePortableBackup(
        backup.directory,
        pinnedByPath: backup.pinnedByPath,
      );

  Map<String, dynamic> _decodeManifest(Object? content) {
    try {
      final decoded = jsonDecode(utf8.decode(content as List<int>));
      if (decoded is! Map) throw const FormatException();
      final manifest = Map<String, dynamic>.from(decoded);
      if (manifest['formatVersion'] != 1) {
        throw const BackupArchiveException(
          'This backup format is not supported.',
        );
      }
      return manifest;
    } on BackupArchiveException {
      rethrow;
    } catch (_) {
      throw const BackupArchiveException('The backup manifest is invalid.');
    }
  }

  bool _safeArchivePath(String path) =>
      path == backupManifestName ||
      (path.startsWith(_notesDirectory) &&
          _safeLibraryPath(path.substring(_notesDirectory.length)));

  bool _safeLibraryPath(String path) {
    final normalized = p.normalize(path).replaceAll('\\', '/');
    return path.isNotEmpty &&
        !p.isAbsolute(normalized) &&
        normalized != '..' &&
        !normalized.startsWith('../') &&
        normalized == path;
  }
}

class PreparedBackup {
  const PreparedBackup(this.directory, this.pinnedByPath);
  final Directory directory;
  final Map<String, bool> pinnedByPath;
}
