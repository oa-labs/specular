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
const syncIntervalStorageKey = 'github_sync_interval_minutes';

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
      if (result.message == 'Synced with GitHub') {
        await storage.write(key: initialSyncCompletedStorageKey, value: 'true');
      }
      return result.isSuccess || result.error == null;
    } finally {
      await database.close();
    }
  });
}

class SyncScheduler {
  static var _initialized = false;
  static const defaultIntervalMinutes = 15;
  static const intervalChoices = <int>[15, 30, 60, 180, 360, 720, 1440];

  static Future<void> initialize(FlutterSecureStorage storage) async {
    if (_initialized) return;
    await Workmanager().initialize(specularBackgroundDispatcher);
    _initialized = true;
    await _schedulePeriodic(await intervalFromStorage(storage));
  }

  static Future<int> intervalFromStorage(FlutterSecureStorage storage) async {
    final stored = int.tryParse(
      await storage.read(key: syncIntervalStorageKey) ?? '',
    );
    return intervalChoices.contains(stored) ? stored! : defaultIntervalMinutes;
  }

  static Future<void> setInterval(
    FlutterSecureStorage storage,
    int minutes,
  ) async {
    if (!intervalChoices.contains(minutes)) {
      throw ArgumentError.value(
        minutes,
        'minutes',
        'Unsupported sync interval',
      );
    }
    await storage.write(key: syncIntervalStorageKey, value: '$minutes');
    if (_initialized) await _schedulePeriodic(minutes);
  }

  static Future<void> _schedulePeriodic(int minutes) async {
    // WorkManager keeps periodic work by unique name. Cancel first so a changed
    // user preference replaces the old cadence instead of being ignored.
    await Workmanager().cancelByUniqueName(_periodicName);
    await Workmanager().registerPeriodicTask(
      _periodicName,
      _taskName,
      frequency: Duration(minutes: minutes),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    );
  }

  static Future<void> enqueue() async {
    if (!_initialized) return;
    await Workmanager().registerOneOffTask(
      _immediateName,
      _taskName,
      initialDelay: const Duration(seconds: 5),
      constraints: Constraints(networkType: NetworkType.connected),
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: const Duration(minutes: 1),
      existingWorkPolicy: ExistingWorkPolicy.replace,
    );
  }
}
