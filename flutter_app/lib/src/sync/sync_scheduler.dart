import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:workmanager/workmanager.dart';

import '../data/app_database.dart';
import '../data/note_repository.dart';
import '../platform/legacy_bridge.dart';
import '../voice/voice_service.dart';
import 'github_sync.dart';

const _periodicName = 'github_periodic_sync';
const _immediateName = 'github_immediate_sync';
const _taskName = 'github_sync';

@pragma('vm:entry-point')
void specularBackgroundDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    const storage = FlutterSecureStorage();
    if (task == VoiceService.retryTask) {
      return VoiceService.processBackgroundRetry(storage, inputData);
    }
    final state = await LegacyBridge.readBackgroundState(storage);
    if (state == null) return true;
    final database = AppDatabase.openLegacy(state);
    try {
      final result = await GitHubSyncEngine(
        NoteRepository(database, Directory(state.notesPath)),
        storage,
      ).sync();
      return result.isSuccess || result.error == null;
    } finally {
      await database.close();
    }
  });
}

class SyncScheduler {
  static var _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) return;
    await Workmanager().initialize(specularBackgroundDispatcher);
    await Workmanager().registerPeriodicTask(
      _periodicName,
      _taskName,
      frequency: const Duration(minutes: 15),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    );
    _initialized = true;
  }

  static Future<void> enqueue() async {
    if (!_initialized) return;
    await Workmanager().registerOneOffTask(
      _immediateName,
      _taskName,
      initialDelay: const Duration(seconds: 5),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingWorkPolicy.replace,
    );
  }
}
