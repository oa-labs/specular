import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:workmanager/workmanager.dart';

import '../data/app_database.dart';
import '../data/note_repository.dart';
import '../platform/legacy_bridge.dart';
import '../platform/platform_capabilities.dart';
import '../voice/voice_service.dart';
import 'github_sync.dart';

const _periodicName = 'github_periodic_sync';
const _immediateName = 'github_immediate_sync';
const _taskName = 'github_sync';
const syncIntervalStorageKey = 'github_sync_interval_minutes';

/// Progress callbacks are intentionally synchronous so the sync engine never
/// waits on UI plumbing. Persisting every counter increment, however, makes a
/// 122-change upload enqueue hundreds of encrypted-storage writes behind the
/// network work. Keep just the newest state while a write is in flight.
class _SharedProgressReporter {
  _SharedProgressReporter(this._storage);

  final FlutterSecureStorage _storage;
  SyncProgress? _latest;
  Future<void>? _writing;

  void report(SyncProgress progress) {
    _latest = progress;
    _writing ??= _drain();
  }

  Future<void> _drain() async {
    while (_latest != null) {
      final progress = _latest!;
      _latest = null;
      try {
        await SharedSyncProgress.save(_storage, progress);
      } catch (_) {
        // The sync itself remains safe if this optional UI status cannot be
        // persisted in the headless isolate.
      }
    }
    _writing = null;
  }

  Future<void> flush() async {
    while (_writing != null) {
      await _writing;
    }
  }
}

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
    final progressReporter = _SharedProgressReporter(storage);

    try {
      final result = await GitHubSyncEngine(
        NoteRepository(database, Directory(state.notesPath)),
        storage,
      ).sync(onProgress: progressReporter.report);
      await progressReporter.flush();
      if (result.message == 'Synced with GitHub') {
        await Future.wait([
          storage.write(key: initialSyncCompletedStorageKey, value: 'true'),
          storage.write(
            key: lastSuccessfulGitHubSyncStorageKey,
            value: DateTime.now().toUtc().toIso8601String(),
          ),
        ]);
      }
      return result.isSuccess || result.error == null;
    } finally {
      await progressReporter.flush();
      try {
        await SharedSyncProgress.clear(storage);
      } catch (_) {
        // A stale status is ignored whenever the durable lease is inactive.
      }
      await database.close();
    }
  });
}

class SyncScheduler {
  static var _initialized = false;
  static var _configuredInterval = defaultIntervalMinutes;
  static Timer? _desktopPeriodicTimer;
  static Timer? _desktopQueuedSync;
  static Future<void> Function()? _foregroundSync;
  static const defaultIntervalMinutes = 15;
  static const intervalChoices = <int>[15, 30, 60, 180, 360, 720, 1440];

  static Future<void> initialize(FlutterSecureStorage storage) async {
    if (_initialized) return;
    if (PlatformCapabilities.current.supportsDurableBackgroundSync) {
      await Workmanager().initialize(specularBackgroundDispatcher);
    }
    _initialized = true;
    final interval = await intervalFromStorage(storage);
    _configuredInterval = interval;
    if (PlatformCapabilities.current.supportsDurableBackgroundSync) {
      await _schedulePeriodic(interval);
    }
  }

  /// Registers the sync function owned by the visible Flutter application.
  /// On macOS this powers startup/resume and best-effort timer sync only while
  /// the app is alive; it never claims to run after the process has quit.
  static void registerForegroundSync(Future<void> Function() sync) {
    _foregroundSync = sync;
    if (PlatformCapabilities.current.supportsBestEffortInProcessSync &&
        _initialized) {
      unawaited(_scheduleDesktopPeriodic());
    }
  }

  static Future<void> syncOnAppResume() async {
    if (!PlatformCapabilities.current.supportsBestEffortInProcessSync) return;
    await _runForegroundSync();
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
    _configuredInterval = minutes;
    if (!_initialized) return;
    if (PlatformCapabilities.current.supportsDurableBackgroundSync) {
      await _schedulePeriodic(minutes);
    } else if (PlatformCapabilities.current.supportsBestEffortInProcessSync) {
      await _scheduleDesktopPeriodic(interval: minutes);
    }
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
    if (PlatformCapabilities.current.supportsBestEffortInProcessSync) {
      _desktopQueuedSync?.cancel();
      _desktopQueuedSync = Timer(
        const Duration(seconds: 5),
        () => unawaited(_runForegroundSync()),
      );
      return;
    }
    if (!PlatformCapabilities.current.supportsDurableBackgroundSync) return;
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

  static Future<void> _scheduleDesktopPeriodic({int? interval}) async {
    _desktopPeriodicTimer?.cancel();
    final minutes = interval ?? _configuredInterval;
    _desktopPeriodicTimer = Timer.periodic(
      Duration(minutes: minutes),
      (_) => unawaited(_runForegroundSync()),
    );
  }

  static Future<void> _runForegroundSync() async {
    final sync = _foregroundSync;
    if (sync == null) return;
    try {
      await sync();
    } catch (_) {
      // Foreground sync presents failures through the existing sync UI. A
      // timer must not turn a transient network error into an uncaught error.
    }
  }
}
