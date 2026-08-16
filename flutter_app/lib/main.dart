import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'src/data/app_database.dart';
import 'src/data/note_repository.dart';
import 'src/platform/legacy_bridge.dart';
import 'src/sync/sync_scheduler.dart';
import 'src/ui/specular_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final bridge = LegacyBridge();
  final state = await bridge.readState();
  const secureStorage = FlutterSecureStorage();
  await bridge.migrateSecrets(state, secureStorage);
  final initialLocation = initialLocationFor(
    platformRoute: WidgetsBinding.instance.platformDispatcher.defaultRouteName,
    savedRoute: await secureStorage.read(key: lastRouteStorageKey),
  );
  final themeMode = themeModeFromStorage(
    await secureStorage.read(key: themeModeStorageKey),
  );
  final textScale = textScaleFromStorage(
    await secureStorage.read(key: textScaleStorageKey),
  );
  await SyncScheduler.initialize(secureStorage);
  final database = AppDatabase.openLegacy(state);
  final repository = NoteRepository(
    database,
    Directory(state.notesPath),
    onLocalChange: SyncScheduler.enqueue,
  );
  runApp(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        noteRepositoryProvider.overrideWithValue(repository),
        secureStorageProvider.overrideWithValue(secureStorage),
        themeModeControllerProvider.overrideWith(
          (_) => ThemeModeController(themeMode),
        ),
        textScaleControllerProvider.overrideWith(
          (_) => TextScaleController(textScale),
        ),
      ],
      child: SpecularApp(initialLocation: initialLocation),
    ),
  );
  // Existing Android installs already have a Room index. Never hold Flutter's
  // first frame behind a full filesystem re-index; only seed a genuinely empty
  // database, after the list screen has rendered.
  unawaited(repository.importExistingFilesIfNeeded());
  unawaited(repository.migrateGlobalTaskIndex());
  unawaited(repository.rebuildLinkIndex());
}
