import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

/// Android upgrade boundary. Desktop installations use their own app-support
/// directory and Keychain entries; they do not read Android-private data.
class LegacyBridge {
  static const _channel = MethodChannel('com.specular.android/legacy');
  static const _completeKey = 'legacy_migration_complete';

  Future<LegacyState> readState() async {
    if (!Platform.isAndroid) {
      final support = await getApplicationSupportDirectory();
      return LegacyState(
        notesPath: '${support.path}${Platform.pathSeparator}notes',
        databasePath: '${support.path}${Platform.pathSeparator}reflect.db',
        migrationComplete: true,
        deselectedFolders: const [],
        secrets: const {},
      );
    }
    final raw = Map<Object?, Object?>.from(
      await _channel.invokeMethod<Map<Object?, Object?>>('readLegacyState') ??
          const {},
    );
    return LegacyState(
      notesPath: raw['notesPath'] as String,
      databasePath: raw['databasePath'] as String,
      migrationComplete: raw['migrationComplete'] as bool? ?? false,
      deselectedFolders: List<String>.from(
        raw['deselectedFolders'] as List? ?? const [],
      ),
      secrets: Map<String, Object?>.from(raw['secrets'] as Map? ?? const {}),
    );
  }

  Future<void> migrateSecrets(
    LegacyState state,
    FlutterSecureStorage storage,
  ) async {
    // These non-secret locations are also needed by WorkManager's headless
    // isolate. Keep writing them on upgrades where migration had already run.
    await storage.write(key: _notesPathKey, value: state.notesPath);
    await storage.write(key: _databasePathKey, value: state.databasePath);
    if (await storage.read(key: _completeKey) == 'true') return;
    for (final entry in state.secrets.entries) {
      final value = entry.value;
      if (value is String && value.isNotEmpty) {
        await storage.write(key: entry.key, value: value);
      }
      if (value is bool) {
        await storage.write(key: entry.key, value: value.toString());
      }
    }
    if (state.deselectedFolders.isNotEmpty) {
      await storage.write(
        key: 'deselected_folders',
        value: state.deselectedFolders.join('\u001f'),
      );
    }
    await storage.write(key: _completeKey, value: 'true');
    if (Platform.isAndroid) {
      await _channel.invokeMethod<void>('markLegacyMigrationComplete');
    }
  }

  static Future<LegacyState?> readBackgroundState(
    FlutterSecureStorage storage,
  ) async {
    final notesPath = await storage.read(key: _notesPathKey);
    final databasePath = await storage.read(key: _databasePathKey);
    if (notesPath == null || databasePath == null) return null;
    return LegacyState(
      notesPath: notesPath,
      databasePath: databasePath,
      migrationComplete: true,
      deselectedFolders: const [],
      secrets: const {},
    );
  }

  static const _notesPathKey = 'legacy_notes_path';
  static const _databasePathKey = 'legacy_database_path';
}

class LegacyState {
  const LegacyState({
    required this.notesPath,
    required this.databasePath,
    required this.migrationComplete,
    required this.deselectedFolders,
    required this.secrets,
  });

  final String notesPath;
  final String databasePath;
  final bool migrationComplete;
  final List<String> deselectedFolders;
  final Map<String, Object?> secrets;
}
