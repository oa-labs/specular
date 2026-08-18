import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../data/note_repository.dart';
import '../domain/markdown.dart';
import '../domain/note.dart';

const initialSyncCompletedStorageKey = 'initial_sync_completed';
const syncDiagnosticsStorageKey = 'github_sync_diagnostics';
const lastSuccessfulGitHubSyncStorageKey = 'last_successful_github_sync_at';

const _remoteChangedConflictReason =
    'Conflict preserved: the remote note changed while local edits were pending.';
const _remoteMoveConflictReason =
    'Conflict preserved: the remote note moved while local edits were pending.';
const _remoteDeletionConflictReason =
    'Conflict preserved: the remote note was deleted while local edits were pending.';

/// A concrete unit of sync work reported to the foreground UI. The totals are
/// based on the repository snapshot, rather than an indeterminate timer, so
/// first-time setup can say exactly how far through the import it is.
class SyncProgress {
  const SyncProgress({
    required this.message,
    this.completed,
    this.total,
    this.itemLabel,
  });

  final String message;
  final int? completed;
  final int? total;
  final String? itemLabel;
}

typedef SyncProgressCallback = void Function(SyncProgress progress);

/// Lightweight progress shared by the foreground Flutter engine and
/// WorkManager's headless isolate. The database lease determines whether this
/// status is live; storage only carries the display details.
class SharedSyncProgress {
  static const _messageKey = 'github_sync_progress_message';
  static const _completedKey = 'github_sync_progress_completed';
  static const _totalKey = 'github_sync_progress_total';
  static const _itemLabelKey = 'github_sync_progress_item_label';

  static Future<void> save(
    FlutterSecureStorage storage,
    SyncProgress progress,
  ) async {
    await Future.wait([
      storage.write(key: _messageKey, value: progress.message),
      storage.write(key: _completedKey, value: progress.completed?.toString()),
      storage.write(key: _totalKey, value: progress.total?.toString()),
      storage.write(key: _itemLabelKey, value: progress.itemLabel),
    ]);
  }

  static Future<SyncProgress?> load(FlutterSecureStorage storage) async {
    final values = await Future.wait([
      storage.read(key: _messageKey),
      storage.read(key: _completedKey),
      storage.read(key: _totalKey),
      storage.read(key: _itemLabelKey),
    ]);
    final message = values[0];
    if (message == null || message.isEmpty) return null;
    return SyncProgress(
      message: message,
      completed: int.tryParse(values[1] ?? ''),
      total: int.tryParse(values[2] ?? ''),
      itemLabel: values[3],
    );
  }

  static Future<void> clear(FlutterSecureStorage storage) => Future.wait([
    storage.delete(key: _messageKey),
    storage.delete(key: _completedKey),
    storage.delete(key: _totalKey),
    storage.delete(key: _itemLabelKey),
  ]);
}

class SyncLogEntry {
  const SyncLogEntry({required this.timestamp, required this.message});

  final DateTime timestamp;
  final String message;

  Map<String, String> encode() => {
    'timestamp': timestamp.toUtc().toIso8601String(),
    'message': message,
  };

  static SyncLogEntry? decode(Object? value) {
    if (value is! Map) return null;
    final timestamp = DateTime.tryParse(value['timestamp']?.toString() ?? '');
    final message = value['message']?.toString();
    if (timestamp == null || message == null || message.isEmpty) return null;
    return SyncLogEntry(timestamp: timestamp.toLocal(), message: message);
  }
}

/// Settings and a small, non-sensitive troubleshooting trail for GitHub sync.
/// It deliberately contains phase/error text only, never request data, note
/// content, repository credentials, or GitHub tokens.
class SyncDiagnostics {
  static const _logKey = 'github_sync_diagnostic_log';
  static const _maxEntries = 30;

  static Future<bool> isEnabled(FlutterSecureStorage storage) async =>
      await storage.read(key: syncDiagnosticsStorageKey) == 'true';

  static Future<void> setEnabled(FlutterSecureStorage storage, bool enabled) =>
      storage.write(key: syncDiagnosticsStorageKey, value: '$enabled');

  static bool isDetailedStage(SyncProgress progress) {
    if (progress.itemLabel != null) return false;
    if (progress.message.startsWith('Conflict preserved:')) return true;
    return switch (progress.message) {
      'Remote is up to date…' ||
      'Checking deleted notes…' ||
      'Creating GitHub commit…' ||
      'Publishing GitHub commit…' ||
      'Recording synced notes locally…' ||
      'Remote changes detected; retrying…' => true,
      _ => false,
    };
  }

  static Future<List<SyncLogEntry>> read(FlutterSecureStorage storage) async {
    try {
      final value = await storage.read(key: _logKey);
      if (value == null || value.isEmpty) return const [];
      final decoded = jsonDecode(value);
      if (decoded is! List) return const [];
      return decoded
          .map(SyncLogEntry.decode)
          .whereType<SyncLogEntry>()
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  static Future<void> append(
    FlutterSecureStorage storage,
    String message,
  ) async {
    final entries = await read(storage);
    final updated = [
      ...entries,
      SyncLogEntry(timestamp: DateTime.now(), message: message),
    ];
    final retained = updated.length > _maxEntries
        ? updated.sublist(updated.length - _maxEntries)
        : updated;
    await storage.write(
      key: _logKey,
      value: jsonEncode(retained.map((entry) => entry.encode()).toList()),
    );
  }

  static Future<void> clear(FlutterSecureStorage storage) =>
      storage.delete(key: _logKey);
}

class SyncResult {
  const SyncResult._(this.message, [this.error, this.noRemoteChanges = false]);
  const SyncResult.success(String message, {bool noRemoteChanges = false})
    : this._(message, null, noRemoteChanges);
  const SyncResult.failure(String message, Object error)
    : this._(message, error);
  const SyncResult.notConfigured() : this._('GitHub sync is not configured.');
  final String message;
  final Object? error;
  final bool noRemoteChanges;
  bool get isSuccess =>
      error == null && message != 'GitHub sync is not configured.';
}

class _ConcurrentRefUpdate implements Exception {
  const _ConcurrentRefUpdate(this.error);

  final DioException error;
}

/// GitHub uses 422 for several distinct failures. Only a non-fast-forward
/// ref update is worth retrying; retrying a protected branch or validation
/// failure needlessly uploads every local blob a second time.
bool _isRetryableRefUpdate(DioException error) {
  if (error.response?.statusCode == 409) return true;
  if (error.response?.statusCode != 422) return false;
  final detail = _githubErrorDetail(error).toLowerCase();
  return detail.contains('fast forward') ||
      detail.contains('reference update failed') ||
      detail.contains('reference update');
}

String _githubErrorDetail(DioException error) {
  final data = error.response?.data;
  if (data is! Map) return '';
  final parts = <String>[];
  final message = data['message']?.toString();
  if (message != null && message.isNotEmpty) parts.add(message);
  final errors = data['errors'];
  if (errors is List) {
    for (final entry in errors.whereType<Map>()) {
      for (final key in const ['message', 'code', 'field', 'resource']) {
        final value = entry[key]?.toString();
        if (value != null && value.isNotEmpty) parts.add(value);
      }
    }
  }
  return parts.join(': ');
}

class GitHubSettings {
  const GitHubSettings({
    required this.token,
    required this.owner,
    required this.repo,
  });
  final String token;
  final String owner;
  final String repo;

  static Future<GitHubSettings?> load(FlutterSecureStorage storage) async {
    final token = (await storage.read(key: 'github_token'))?.trim() ?? '';
    final owner = (await storage.read(key: 'repo_owner'))?.trim() ?? '';
    final repo = (await storage.read(key: 'repo_name'))?.trim() ?? '';
    return token.isEmpty || owner.isEmpty || repo.isEmpty
        ? null
        : GitHubSettings(token: token, owner: owner, repo: repo);
  }
}

class GitHubRepository {
  const GitHubRepository({
    required this.id,
    required this.owner,
    required this.name,
    required this.fullName,
    required this.defaultBranch,
    required this.isPrivate,
  });

  final int id;
  final String owner;
  final String name;
  final String fullName;
  final String defaultBranch;
  final bool isPrivate;
}

class GitHubRepositoryException implements Exception {
  const GitHubRepositoryException(this.message);

  final String message;

  @override
  String toString() => message;
}

class _RemoteSnapshot {
  const _RemoteSnapshot({
    required this.branch,
    required this.commitSha,
    required this.treeSha,
  });

  final String branch;
  final String commitSha;
  final String treeSha;
}

class _PullResult {
  const _PullResult({required this.snapshot, required this.noRemoteChanges});

  final _RemoteSnapshot snapshot;
  final bool noRemoteChanges;
}

/// The branch head and tree from a completed sync. Keeping this outside the
/// note database lets an unchanged remote be recognized with one ref request,
/// rather than downloading and walking the full tree again.
class _CachedRemoteSnapshot {
  const _CachedRemoteSnapshot({
    required this.branch,
    required this.commitSha,
    required this.treeSha,
  });

  final String branch;
  final String commitSha;
  final String treeSha;

  _RemoteSnapshot toSnapshot() =>
      _RemoteSnapshot(branch: branch, commitSha: commitSha, treeSha: treeSha);

  String encode() => jsonEncode({
    'branch': branch,
    'commitSha': commitSha,
    'treeSha': treeSha,
  });

  static _CachedRemoteSnapshot? decode(String value) {
    try {
      final data = jsonDecode(value);
      if (data is! Map) return null;
      final branch = data['branch'];
      final commitSha = data['commitSha'];
      final treeSha = data['treeSha'];
      if (branch is! String || commitSha is! String || treeSha is! String) {
        return null;
      }
      if (branch.isEmpty || commitSha.isEmpty || treeSha.isEmpty) return null;
      return _CachedRemoteSnapshot(
        branch: branch,
        commitSha: commitSha,
        treeSha: treeSha,
      );
    } on FormatException {
      return null;
    }
  }
}

class GitHubSyncEngine {
  GitHubSyncEngine(
    this._repository,
    FlutterSecureStorage storage, {
    Dio? dio,
    Future<GitHubSettings?> Function()? settingsLoader,
    Future<String?> Function(String key)? cacheRead,
    Future<void> Function(String key, String value)? cacheWrite,
  }) : _settingsLoader = settingsLoader ?? (() => GitHubSettings.load(storage)),
       _storage = storage,
       _cacheRead = cacheRead ?? ((key) => storage.read(key: key)),
       _cacheWrite =
           cacheWrite ??
           ((key, value) => storage.write(key: key, value: value)),
       _dio =
           dio ??
           Dio(
             BaseOptions(
               baseUrl: 'https://api.github.com',
               connectTimeout: const Duration(seconds: 12),
               sendTimeout: const Duration(seconds: 20),
               receiveTimeout: const Duration(seconds: 30),
               headers: const {
                 'Accept': 'application/vnd.github+json',
                 'X-GitHub-Api-Version': '2022-11-28',
               },
             ),
           );

  final NoteRepository _repository;
  final FlutterSecureStorage _storage;
  final Future<GitHubSettings?> Function() _settingsLoader;
  final Future<String?> Function(String key) _cacheRead;
  final Future<void> Function(String key, String value) _cacheWrite;
  final Dio _dio;
  Future<void> _tail = Future.value();
  Future<void> _diagnosticWrites = Future.value();
  String? _lastLoggedStage;

  static const _maxConcurrentChangeRetries = 1;

  Future<SyncResult> sync({
    SyncProgressCallback? onProgress,
    bool forceFullRemoteScan = false,
  }) => _serialized(() async {
    _lastLoggedStage = null;
    void report(SyncProgress progress) {
      onProgress?.call(progress);
      _recordDiagnostic(progress);
    }

    report(const SyncProgress(message: 'Connecting to GitHub…'));
    final settings = await _settingsLoader();
    if (settings == null) return const SyncResult.notConfigured();
    final lease = await _repository.acquireSyncLease(
      owner: 'github-${DateTime.now().microsecondsSinceEpoch}-$hashCode',
    );
    if (lease == null) {
      return const SyncResult.success('Another sync is already running.');
    }
    final renewal = Timer.periodic(const Duration(minutes: 1), (_) {
      unawaited(_repository.renewSyncLease(lease));
    });
    try {
      for (var attempt = 0; ; attempt++) {
        final pull = await _pull(
          settings,
          onProgress: report,
          forceFullRemoteScan: forceFullRemoteScan,
        );
        try {
          final completedSnapshot = await _push(
            settings,
            pull.snapshot,
            onProgress: report,
          );
          await _saveCachedSnapshot(settings, completedSnapshot);
          report(const SyncProgress(message: 'Sync complete'));
          await _flushDiagnostics();
          return SyncResult.success(
            'Synced with GitHub',
            noRemoteChanges: pull.noRemoteChanges,
          );
        } on _ConcurrentRefUpdate {
          if (attempt >= _maxConcurrentChangeRetries) rethrow;
          report(
            const SyncProgress(message: 'Remote changes detected; retrying…'),
          );
        }
      }
    } on _ConcurrentRefUpdate catch (conflict) {
      final message = _friendlyError(conflict.error);
      _recordDiagnostic(SyncProgress(message: 'Failed: $message'));
      await _flushDiagnostics();
      return SyncResult.failure(message, conflict.error);
    } on DioException catch (error) {
      final message = _friendlyError(error);
      _recordDiagnostic(SyncProgress(message: 'Failed: $message'));
      await _flushDiagnostics();
      return SyncResult.failure(message, error);
    } catch (error) {
      final message = 'Sync failed: $error';
      _recordDiagnostic(SyncProgress(message: 'Failed: $message'));
      await _flushDiagnostics();
      return SyncResult.failure(message, error);
    } finally {
      renewal.cancel();
      await _repository.releaseSyncLease(lease);
    }
  });

  Future<T> _serialized<T>(Future<T> Function() operation) {
    final result = _tail.then((_) => operation());
    _tail = result.then<void>((_) {}, onError: (error, stackTrace) {});
    return result;
  }

  void _recordDiagnostic(SyncProgress progress) {
    // Counter changes are intentionally omitted: they would make the log
    // noisy and turn a large sync into hundreds of encrypted storage writes.
    if (progress.itemLabel != null || progress.message == _lastLoggedStage) {
      return;
    }
    _lastLoggedStage = progress.message;
    _diagnosticWrites = _diagnosticWrites.then((_) async {
      try {
        await SyncDiagnostics.append(_storage, progress.message);
      } catch (_) {
        // Diagnostics are optional and must never prevent a sync.
      }
    });
  }

  Future<void> _flushDiagnostics() => _diagnosticWrites;

  Options _options(GitHubSettings settings) =>
      Options(headers: {'Authorization': 'Bearer ${settings.token}'});

  /// Lists repositories the supplied token can access for the Settings picker.
  Future<List<GitHubRepository>> listRepositories(String token) async {
    final normalizedToken = token.trim();
    if (normalizedToken.isEmpty) {
      throw const GitHubRepositoryException(
        'Enter a GitHub personal access token first.',
      );
    }
    try {
      final repositories = <GitHubRepository>[];
      for (var page = 1; ; page++) {
        final response = await _dio.get<List<dynamic>>(
          '/user/repos',
          queryParameters: {
            'affiliation': 'owner,collaborator,organization_member',
            'per_page': 100,
            'page': page,
            'sort': 'updated',
          },
          options: Options(
            headers: {'Authorization': 'Bearer $normalizedToken'},
          ),
        );
        final rows = response.data ?? const <dynamic>[];
        repositories.addAll(
          rows.whereType<Map>().map((row) {
            final owner = Map<String, dynamic>.from(
              row['owner'] as Map? ?? const <String, dynamic>{},
            );
            return GitHubRepository(
              id: row['id'] as int,
              owner: owner['login'] as String,
              name: row['name'] as String,
              fullName: row['full_name'] as String,
              defaultBranch: row['default_branch'] as String? ?? 'main',
              isPrivate: row['private'] as bool? ?? true,
            );
          }),
        );
        if (rows.length < 100) return repositories;
      }
    } on DioException catch (error) {
      throw GitHubRepositoryException(_friendlyError(error));
    }
  }

  /// Confirms that a selected repository exists and has an initialized branch.
  /// A repository with no Markdown is a valid first backup destination.
  Future<void> validateRepository(
    String token,
    GitHubRepository repository,
  ) async {
    final normalizedToken = token.trim();
    if (normalizedToken.isEmpty) {
      throw const GitHubRepositoryException(
        'Enter a GitHub personal access token first.',
      );
    }
    final settings = GitHubSettings(
      token: normalizedToken,
      owner: repository.owner,
      repo: repository.name,
    );
    try {
      final ref = await _dio.get<Map<String, dynamic>>(
        '/repos/${repository.owner}/${repository.name}/git/ref/heads/${Uri.encodeComponent(repository.defaultBranch)}',
        options: _options(settings),
      );
      final sha =
          (ref.data!['object'] as Map<String, dynamic>)['sha'] as String;
      final commit = await _dio.get<Map<String, dynamic>>(
        '/repos/${repository.owner}/${repository.name}/git/commits/$sha',
        options: _options(settings),
      );
      final treeSha =
          (commit.data!['tree'] as Map<String, dynamic>)['sha'] as String;
      await _allTreeEntries(settings, treeSha);
    } on DioException catch (error) {
      throw GitHubRepositoryException(_friendlyError(error));
    }
  }

  /// Creates an initialized private repository for the authenticated user.
  /// `auto_init` gives the sync engine a branch to pull before its first push.
  Future<GitHubRepository> createPrivateRepository(
    String token, {
    required String name,
  }) async {
    final normalizedToken = token.trim();
    final normalizedName = name.trim();
    if (normalizedToken.isEmpty || normalizedName.isEmpty) {
      throw const GitHubRepositoryException('Enter a repository name first.');
    }
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/user/repos',
        data: {
          'name': normalizedName,
          'description': 'Private Markdown backup created by Specular.',
          'private': true,
          'auto_init': true,
        },
        options: Options(headers: {'Authorization': 'Bearer $normalizedToken'}),
      );
      final row = response.data!;
      final owner = Map<String, dynamic>.from(
        row['owner'] as Map? ?? const <String, dynamic>{},
      );
      return GitHubRepository(
        id: row['id'] as int,
        owner: owner['login'] as String,
        name: row['name'] as String,
        fullName: row['full_name'] as String,
        defaultBranch: row['default_branch'] as String? ?? 'main',
        isPrivate: true,
      );
    } on DioException catch (error) {
      throw GitHubRepositoryException(_friendlyError(error));
    }
  }

  /// Validates manually entered coordinates before a repository switch clears
  /// the local mirror. The API supplies the default branch, so this works for
  /// repositories that do not use `main`.
  Future<void> validateRepositoryCoordinates(
    String token, {
    required String owner,
    required String repo,
  }) async {
    final normalizedToken = token.trim();
    if (normalizedToken.isEmpty ||
        owner.trim().isEmpty ||
        repo.trim().isEmpty) {
      throw const GitHubRepositoryException(
        'Enter a GitHub token, repository owner, and repository name first.',
      );
    }
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/repos/${Uri.encodeComponent(owner.trim())}/${Uri.encodeComponent(repo.trim())}',
        options: Options(headers: {'Authorization': 'Bearer $normalizedToken'}),
      );
      final data = response.data!;
      final repositoryOwner = Map<String, dynamic>.from(
        data['owner'] as Map? ?? const <String, dynamic>{},
      );
      await validateRepository(
        normalizedToken,
        GitHubRepository(
          id: data['id'] as int,
          owner: repositoryOwner['login'] as String,
          name: data['name'] as String,
          fullName: data['full_name'] as String,
          defaultBranch: data['default_branch'] as String? ?? 'main',
          isPrivate: data['private'] as bool? ?? true,
        ),
      );
    } on DioException catch (error) {
      throw GitHubRepositoryException(_friendlyError(error));
    }
  }

  Future<_PullResult> _pull(
    GitHubSettings settings, {
    SyncProgressCallback? onProgress,
    bool forceFullRemoteScan = false,
  }) async {
    final cached = await _loadCachedSnapshot(settings);
    var branch = cached?.branch ?? await _defaultBranch(settings);
    late Response<Map<String, dynamic>> ref;
    try {
      ref = await _branchRef(settings, branch);
    } on DioException catch (error) {
      // A repository's default branch can change. Resolve it once again when
      // an otherwise valid cached branch no longer exists.
      if (cached == null || error.response?.statusCode != 404) rethrow;
      branch = await _defaultBranch(settings);
      ref = await _branchRef(settings, branch);
    }
    final commitSha =
        (ref.data!['object'] as Map<String, dynamic>)['sha'] as String;
    if (cached != null &&
        cached.branch == branch &&
        cached.commitSha == commitSha &&
        !forceFullRemoteScan) {
      onProgress?.call(const SyncProgress(message: 'Remote is up to date…'));
      return _PullResult(snapshot: cached.toSnapshot(), noRemoteChanges: true);
    }
    final commit = await _dio.get<Map<String, dynamic>>(
      '/repos/${settings.owner}/${settings.repo}/git/commits/$commitSha',
      options: _options(settings),
    );
    final treeSha =
        (commit.data!['tree'] as Map<String, dynamic>)['sha'] as String;
    final changedFiles = cached == null || forceFullRemoteScan
        ? null
        : await _compareChangedFiles(settings, cached.commitSha, commitSha);
    if (changedFiles != null) {
      await _applyComparedFiles(settings, changedFiles, onProgress: onProgress);
      final snapshot = _RemoteSnapshot(
        branch: branch,
        commitSha: commitSha,
        treeSha: treeSha,
      );
      await _saveCachedSnapshot(settings, snapshot);
      return _PullResult(snapshot: snapshot, noRemoteChanges: false);
    }
    final entries = await _allTreeEntries(settings, treeSha);
    final markdownEntries = entries.where(_isMarkdownNote).toList();
    onProgress?.call(
      SyncProgress(
        message: 'Checking your notes…',
        completed: 0,
        total: markdownEntries.length,
        itemLabel: 'notes',
      ),
    );
    for (var index = 0; index < markdownEntries.length; index++) {
      final entry = markdownEntries[index];
      final path = entry['path'] as String;
      final remoteSha = entry['sha'] as String;
      final local = await _repository.findByPath(path);
      // The blob SHA is the exact contents identity. A matching baseline means
      // this note has neither changed remotely nor needs to be re-indexed.
      // This also deliberately leaves unsynced local edits alone: their
      // lastRemoteSha still identifies the remote version they were based on.
      if (local?.lastRemoteSha != remoteSha) {
        await _applyRemoteMarkdown(
          settings,
          path,
          remoteSha,
          onConflict: (reason) => _reportConflict(onProgress, reason),
        );
      }
      onProgress?.call(
        SyncProgress(
          message: 'Checking your notes…',
          completed: index + 1,
          total: markdownEntries.length,
          itemLabel: 'notes',
        ),
      );
    }
    await _repository.reconcileRemoteRemovals(
      markdownEntries.map((entry) => entry['path'] as String).toSet(),
      onConflictPreserved: () =>
          _reportConflict(onProgress, _remoteDeletionConflictReason),
    );
    final attachmentEntries = entries.where(_isAttachment).toList();
    onProgress?.call(
      SyncProgress(
        message: 'Checking attachments…',
        completed: 0,
        total: attachmentEntries.length,
        itemLabel: 'attachments',
      ),
    );
    for (var index = 0; index < attachmentEntries.length; index++) {
      final entry = attachmentEntries[index];
      final path = entry['path'] as String;
      final remoteSha = entry['sha'] as String;
      final local = await _repository.attachment(path);
      if (local?.lastRemoteSha != remoteSha && local?.isDirty != true) {
        await _repository.applyRemoteAttachment(
          path: path,
          sha: remoteSha,
          bytes: await _blobBytes(settings, remoteSha),
          mimeType: _mimeFor(path),
        );
      }
      onProgress?.call(
        SyncProgress(
          message: 'Checking attachments…',
          completed: index + 1,
          total: attachmentEntries.length,
          itemLabel: 'attachments',
        ),
      );
    }
    final snapshot = _RemoteSnapshot(
      branch: branch,
      commitSha: commitSha,
      treeSha: treeSha,
    );
    await _saveCachedSnapshot(settings, snapshot);
    return _PullResult(snapshot: snapshot, noRemoteChanges: false);
  }

  /// Uses GitHub's compare response for ordinary fast-forward updates. GitHub
  /// returns no more than 300 changed files here, so larger or non-linear
  /// histories deliberately fall back to the complete tree scan below.
  Future<List<Map<String, dynamic>>?> _compareChangedFiles(
    GitHubSettings settings,
    String base,
    String head,
  ) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/repos/${settings.owner}/${settings.repo}/compare/$base...$head',
        options: _options(settings),
      );
      final data = response.data!;
      final files = data['files'];
      if (data['status'] != 'ahead' || files is! List || files.length >= 300) {
        return null;
      }
      final parsed = files
          .whereType<Map>()
          .map((file) => Map<String, dynamic>.from(file))
          .toList(growable: false);
      return parsed.length == files.length ? parsed : null;
    } on DioException catch (error) {
      // A force-push or an old cached commit can make the comparison
      // unavailable. A complete tree scan remains correct in either case.
      if (error.response?.statusCode == 404 ||
          error.response?.statusCode == 422) {
        return null;
      }
      rethrow;
    }
  }

  Future<void> _applyComparedFiles(
    GitHubSettings settings,
    List<Map<String, dynamic>> files, {
    SyncProgressCallback? onProgress,
  }) async {
    final notes = files
        .where((file) => _isMarkdownPath(file['filename'] as String? ?? ''))
        .toList(growable: false);
    onProgress?.call(
      SyncProgress(
        message: 'Checking notes…',
        completed: 0,
        total: notes.length,
        itemLabel: 'notes',
      ),
    );
    final removedNotePaths = <String>[];
    for (var index = 0; index < notes.length; index++) {
      final file = notes[index];
      final path = file['filename'] as String;
      final status = file['status'] as String? ?? '';
      if (status == 'removed') {
        removedNotePaths.add(path);
      } else {
        final sha = file['sha'] as String?;
        if (sha == null || sha.isEmpty) {
          throw StateError('GitHub returned no blob SHA for $path');
        }
        await _applyRemoteMarkdown(
          settings,
          path,
          sha,
          onConflict: (reason) => _reportConflict(onProgress, reason),
        );
        final previousPath = file['previous_filename'] as String?;
        if (status == 'renamed' && previousPath != null) {
          removedNotePaths.add(previousPath);
        }
      }
      onProgress?.call(
        SyncProgress(
          message: 'Checking notes…',
          completed: index + 1,
          total: notes.length,
          itemLabel: 'notes',
        ),
      );
    }
    for (final path in removedNotePaths) {
      await _repository.reconcileRemoteRemoval(
        path,
        onConflictPreserved: () =>
            _reportConflict(onProgress, _remoteDeletionConflictReason),
      );
    }

    final attachments = files
        .where((file) => _isAttachmentPath(file['filename'] as String? ?? ''))
        .where((file) => file['status'] != 'removed')
        .toList(growable: false);
    onProgress?.call(
      SyncProgress(
        message: 'Checking attachments…',
        completed: 0,
        total: attachments.length,
        itemLabel: 'attachments',
      ),
    );
    for (var index = 0; index < attachments.length; index++) {
      final file = attachments[index];
      final path = file['filename'] as String;
      final sha = file['sha'] as String?;
      if (sha == null || sha.isEmpty) {
        throw StateError('GitHub returned no blob SHA for $path');
      }
      final local = await _repository.attachment(path);
      if (local?.lastRemoteSha != sha && local?.isDirty != true) {
        await _repository.applyRemoteAttachment(
          path: path,
          sha: sha,
          bytes: await _blobBytes(settings, sha),
          mimeType: _mimeFor(path),
        );
      }
      onProgress?.call(
        SyncProgress(
          message: 'Checking attachments…',
          completed: index + 1,
          total: attachments.length,
          itemLabel: 'attachments',
        ),
      );
    }
  }

  Future<void> _applyRemoteMarkdown(
    GitHubSettings settings,
    String path,
    String remoteSha, {
    void Function(String reason)? onConflict,
  }) async {
    final local = await _repository.findByPath(path);
    if (local?.lastRemoteSha == remoteSha) return;
    final content = await _blobContent(settings, remoteSha);
    final parsed = MarkdownContract.parse(content);
    final sameId = await _repository.get(
      MarkdownContract.identityFor(path, parsed.id),
    );
    final localSummaryOnly = await _isSummaryOnlyLocalChange(
      settings,
      local,
      content,
    );
    final sameIdSummaryOnly = await _isSummaryOnlyLocalChange(
      settings,
      sameId,
      content,
    );
    if (localSummaryOnly) {
      await _repository.discardMatchingConflictCopies(local!);
    }
    if (sameIdSummaryOnly && sameId?.id != local?.id) {
      await _repository.discardMatchingConflictCopies(sameId!);
    }
    if (local?.isDirty == true &&
        local?.isPendingDeletion != true &&
        !MarkdownContract.differsOnlyBySummary(local!.rawMarkdown, content) &&
        !localSummaryOnly) {
      if (await _repository.preserveConflict(local)) {
        onConflict?.call(_remoteChangedConflictReason);
      }
    }
    if (sameId != null &&
        sameId.path != path &&
        sameId.isDirty &&
        !MarkdownContract.differsOnlyBySummary(sameId.rawMarkdown, content) &&
        !sameIdSummaryOnly) {
      if (await _repository.preserveConflict(sameId)) {
        onConflict?.call(_remoteMoveConflictReason);
      }
    }
    await _repository.applyRemote(path: path, sha: remoteSha, raw: content);
  }

  /// A generated summary is derived metadata, not a competing local edit.
  /// When the remote note's content has changed, compare the dirty local copy
  /// with the blob it was based on rather than with the newer remote version.
  /// That distinguishes a summary-only mutation from an actual local edit.
  Future<bool> _hasOnlySummaryChangeSinceRemote(
    GitHubSettings settings,
    Note local,
  ) async {
    final baselineSha = local.lastRemoteSha;
    if (baselineSha == null || baselineSha.isEmpty) return false;
    final baseline = await _blobContent(settings, baselineSha);
    return MarkdownContract.differsOnlyBySummary(local.rawMarkdown, baseline);
  }

  Future<bool> _isSummaryOnlyLocalChange(
    GitHubSettings settings,
    Note? local,
    String remoteContent,
  ) async {
    if (local?.isDirty != true || local?.isPendingDeletion == true) {
      return false;
    }
    if (MarkdownContract.differsOnlyBySummary(
      local!.rawMarkdown,
      remoteContent,
    )) {
      return true;
    }
    return _hasOnlySummaryChangeSinceRemote(settings, local);
  }

  void _reportConflict(SyncProgressCallback? onProgress, String reason) {
    onProgress?.call(SyncProgress(message: reason));
  }

  Future<_RemoteSnapshot> _push(
    GitHubSettings settings,
    _RemoteSnapshot snapshot, {
    SyncProgressCallback? onProgress,
  }) async {
    final entries = <String, Map<String, dynamic>>{};
    final acknowledgements = <String, ({int revision, String? sha})>{};
    final attachmentAcks = <String, String>{};
    final attachments = await _repository.dirtyAttachments();
    final notes = await _repository.dirtyNotes();
    final requestedDeletions = <String>{
      for (final note in notes)
        if (note.isPendingDeletion)
          note.pendingRenameFromPath ?? note.path
        else if (note.pendingRenameFromPath != null)
          note.pendingRenameFromPath!,
    };
    Set<String>? remotePaths;
    if (requestedDeletions.isNotEmpty) {
      onProgress?.call(const SyncProgress(message: 'Checking deleted notes…'));
      remotePaths = (await _allTreeEntries(
        settings,
        snapshot.treeSha,
      )).map((entry) => entry['path'] as String).toSet();
    }
    final uploadCount = attachments.length + notes.length;
    onProgress?.call(
      SyncProgress(
        message: uploadCount == 0
            ? 'Finishing up…'
            : 'Uploading local changes…',
        completed: 0,
        total: uploadCount,
        itemLabel: 'changes',
      ),
    );

    // All blobs are assembled against the exact tree pulled above and exposed
    // in one commit. A failed ref update changes no remote files.
    var uploaded = 0;
    for (final attachment in attachments) {
      final bytes = await _repository.attachmentBytes(attachment.path);
      if (bytes != null) {
        final sha = await _createBlob(settings, bytes);
        entries[attachment.path] = _treeBlob(attachment.path, sha);
        attachmentAcks[attachment.path] = sha;
      }
      uploaded++;
      onProgress?.call(
        SyncProgress(
          message: 'Uploading local changes…',
          completed: uploaded,
          total: uploadCount,
          itemLabel: 'changes',
        ),
      );
    }
    for (final note in notes) {
      if (note.isPendingDeletion) {
        final path = note.pendingRenameFromPath ?? note.path;
        // GitHub rejects a tree containing a null SHA for a path that is not
        // present in the base tree. Deletion is already satisfied in that
        // case, so acknowledge it locally without adding an invalid entry.
        if (remotePaths!.contains(path)) {
          entries[path] = _treeDeletion(path);
        }
        acknowledgements[note.id] = (revision: note.localRevision, sha: null);
        uploaded++;
        onProgress?.call(
          SyncProgress(
            message: 'Uploading local changes…',
            completed: uploaded,
            total: uploadCount,
            itemLabel: 'changes',
          ),
        );
        continue;
      }
      final sha = await _createBlob(settings, utf8.encode(note.rawMarkdown));
      entries[note.path] = _treeBlob(note.path, sha);
      if (note.pendingRenameFromPath != null &&
          remotePaths!.contains(note.pendingRenameFromPath)) {
        entries[note.pendingRenameFromPath!] = _treeDeletion(
          note.pendingRenameFromPath!,
        );
      }
      acknowledgements[note.id] = (revision: note.localRevision, sha: sha);
      uploaded++;
      onProgress?.call(
        SyncProgress(
          message: 'Uploading local changes…',
          completed: uploaded,
          total: uploadCount,
          itemLabel: 'changes',
        ),
      );
    }
    if (entries.isEmpty) {
      // The only changes may have been deletions of files that are already
      // absent remotely. They still need to leave the local dirty queue.
      await _repository.acknowledgeNotesSynced(acknowledgements);
      return snapshot;
    }

    onProgress?.call(const SyncProgress(message: 'Saving your changes…'));

    final tree = await _dio.post<Map<String, dynamic>>(
      '/repos/${settings.owner}/${settings.repo}/git/trees',
      data: {'base_tree': snapshot.treeSha, 'tree': entries.values.toList()},
      options: _options(settings),
    );
    final newTreeSha = tree.data?['sha'] as String?;
    if (newTreeSha == null) throw StateError('GitHub returned no tree SHA');
    onProgress?.call(const SyncProgress(message: 'Creating GitHub commit…'));
    final commit = await _dio.post<Map<String, dynamic>>(
      '/repos/${settings.owner}/${settings.repo}/git/commits',
      data: {
        'message': 'Sync Specular notes',
        'tree': newTreeSha,
        'parents': [snapshot.commitSha],
      },
      options: _options(settings),
    );
    final commitSha = commit.data?['sha'] as String?;
    if (commitSha == null) throw StateError('GitHub returned no commit SHA');
    onProgress?.call(const SyncProgress(message: 'Publishing GitHub commit…'));
    try {
      await _dio.patch<void>(
        '/repos/${settings.owner}/${settings.repo}/git/refs/heads/${Uri.encodeComponent(snapshot.branch)}',
        data: {'sha': commitSha, 'force': false},
        options: _options(settings),
      );
    } on DioException catch (error) {
      if (_isRetryableRefUpdate(error)) {
        throw _ConcurrentRefUpdate(error);
      }
      rethrow;
    }
    onProgress?.call(
      const SyncProgress(message: 'Recording synced notes locally…'),
    );
    await _repository.acknowledgeNotesSynced(acknowledgements);
    for (final entry in attachmentAcks.entries) {
      await _repository.markAttachmentSynced(entry.key, entry.value);
    }
    return _RemoteSnapshot(
      branch: snapshot.branch,
      commitSha: commitSha,
      treeSha: newTreeSha,
    );
  }

  Future<String> _defaultBranch(GitHubSettings settings) async {
    final repository = await _dio.get<Map<String, dynamic>>(
      '/repos/${settings.owner}/${settings.repo}',
      options: _options(settings),
    );
    return repository.data!['default_branch'] as String;
  }

  Future<Response<Map<String, dynamic>>> _branchRef(
    GitHubSettings settings,
    String branch,
  ) => _dio.get<Map<String, dynamic>>(
    '/repos/${settings.owner}/${settings.repo}/git/ref/heads/${Uri.encodeComponent(branch)}',
    options: _options(settings),
  );

  String _cacheKey(GitHubSettings settings) {
    final repository =
        '${settings.owner.toLowerCase()}/${settings.repo.toLowerCase()}';
    return 'github_remote_head_${base64UrlEncode(utf8.encode(repository)).replaceAll('=', '')}';
  }

  Future<_CachedRemoteSnapshot?> _loadCachedSnapshot(
    GitHubSettings settings,
  ) async {
    try {
      final value = await _cacheRead(_cacheKey(settings));
      return value == null ? null : _CachedRemoteSnapshot.decode(value);
    } catch (_) {
      // The cache is purely an optimization. A storage issue must never stop a
      // user from syncing their notes.
      return null;
    }
  }

  Future<void> _saveCachedSnapshot(
    GitHubSettings settings,
    _RemoteSnapshot snapshot,
  ) async {
    try {
      await _cacheWrite(
        _cacheKey(settings),
        _CachedRemoteSnapshot(
          branch: snapshot.branch,
          commitSha: snapshot.commitSha,
          treeSha: snapshot.treeSha,
        ).encode(),
      );
    } catch (_) {
      // See _loadCachedSnapshot: syncing safely matters more than caching.
    }
  }

  Map<String, dynamic> _treeBlob(String path, String sha) => {
    'path': path,
    'mode': '100644',
    'type': 'blob',
    'sha': sha,
  };

  Map<String, dynamic> _treeDeletion(String path) => {
    'path': path,
    'mode': '100644',
    'type': 'blob',
    'sha': null,
  };

  Future<String> _createBlob(GitHubSettings settings, List<int> bytes) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/repos/${settings.owner}/${settings.repo}/git/blobs',
      data: {'content': base64Encode(bytes), 'encoding': 'base64'},
      options: _options(settings),
    );
    final sha = response.data?['sha'] as String?;
    if (sha == null) throw StateError('GitHub returned no blob SHA');
    return sha;
  }

  Future<String> _blobContent(GitHubSettings settings, String sha) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/repos/${settings.owner}/${settings.repo}/git/blobs/$sha',
      options: _options(settings),
    );
    final content = response.data?['content'] as String?;
    if (content == null) {
      throw StateError('GitHub returned no content for blob $sha');
    }
    return utf8.decode(base64Decode(content.replaceAll('\n', '')));
  }

  Future<List<int>> _blobBytes(GitHubSettings settings, String sha) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/repos/${settings.owner}/${settings.repo}/git/blobs/$sha',
      options: _options(settings),
    );
    final content = response.data?['content'] as String?;
    if (content == null) {
      throw StateError('GitHub returned no content for blob $sha');
    }
    return base64Decode(content.replaceAll('\n', ''));
  }

  /// Most repositories fit in GitHub's recursive tree response, which makes a
  /// complete remote scan one request. For larger repositories GitHub marks
  /// that response as truncated; then walk individual directories to retain a
  /// complete, snapshot-consistent view.
  Future<List<Map<String, dynamic>>> _allTreeEntries(
    GitHubSettings settings,
    String rootTreeSha,
  ) async {
    final recursive = await _dio.get<Map<String, dynamic>>(
      '/repos/${settings.owner}/${settings.repo}/git/trees/$rootTreeSha',
      queryParameters: const {'recursive': '1'},
      options: _options(settings),
    );
    if (recursive.data?['truncated'] != true) {
      return List<Map<String, dynamic>>.from(
        recursive.data?['tree'] as List? ?? const <dynamic>[],
      ).where((entry) => entry['type'] != 'tree').toList();
    }

    final files = <Map<String, dynamic>>[];
    final pending = <({String prefix, String sha})>[
      (prefix: '', sha: rootTreeSha),
    ];
    while (pending.isNotEmpty) {
      final current = pending.removeLast();
      final response = await _dio.get<Map<String, dynamic>>(
        '/repos/${settings.owner}/${settings.repo}/git/trees/${current.sha}',
        options: _options(settings),
      );
      if (response.data?['truncated'] == true) {
        throw StateError(
          'A repository directory is too large for GitHub tree sync. Split it into subfolders.',
        );
      }
      for (final entry in List<Map<String, dynamic>>.from(
        response.data?['tree'] as List? ?? const <dynamic>[],
      )) {
        final name = entry['path'] as String;
        final path = '${current.prefix}$name';
        if (entry['type'] == 'tree') {
          pending.add((prefix: '$path/', sha: entry['sha'] as String));
        } else {
          files.add({...entry, 'path': path});
        }
      }
    }
    return files;
  }

  bool _isMarkdownNote(Map<String, dynamic> entry) {
    final path = entry['path'] as String? ?? '';
    return entry['type'] == 'blob' && _isMarkdownPath(path);
  }

  bool _isAttachment(Map<String, dynamic> entry) {
    final path = entry['path'] as String? ?? '';
    return entry['type'] == 'blob' && _isAttachmentPath(path);
  }

  bool _isMarkdownPath(String path) =>
      path.endsWith('.md') && !path.endsWith('.reflect.md');

  bool _isAttachmentPath(String path) =>
      (path.startsWith('attachments/') || path.startsWith('assets/')) &&
      !path.endsWith('.reflect.md');

  String? _mimeFor(String path) => switch (path.toLowerCase().split('.').last) {
    'png' => 'image/png',
    'gif' => 'image/gif',
    'webp' => 'image/webp',
    'jpg' || 'jpeg' => 'image/jpeg',
    _ => null,
  };

  String _friendlyError(DioException error) {
    final code = error.response?.statusCode;
    final responseDetail = _githubErrorDetail(error);
    final responseMessage = responseDetail.toLowerCase();
    final rateLimitRemaining = error.response?.headers.value(
      'x-ratelimit-remaining',
    );
    final rateLimitReset = error.response?.headers.value('x-ratelimit-reset');
    final rateLimited =
        rateLimitRemaining == '0' || responseMessage.contains('rate limit');
    if (code == 403 && rateLimited) {
      final resetSeconds = int.tryParse(rateLimitReset ?? '');
      if (resetSeconds != null) {
        final reset = DateTime.fromMillisecondsSinceEpoch(
          resetSeconds * 1000,
        ).toLocal();
        final hour = reset.hour.toString().padLeft(2, '0');
        final minute = reset.minute.toString().padLeft(2, '0');
        return 'GitHub API rate limit reached. Resets at $hour:$minute. '
            'Your local edits are safe.';
      }
      return 'GitHub API rate limit reached. Your local edits are safe.';
    }
    final description = '${error.error}'.toLowerCase();
    if (code == null &&
        (description.contains('failed host lookup') ||
            description.contains('getaddrinfo') ||
            description.contains('name or service not known'))) {
      return 'GitHub DNS lookup failed. Check your connection, VPN, or Private DNS, then try again. Your local edits are safe.';
    }
    if (code == null && error.type == DioExceptionType.connectionError) {
      return 'Network unavailable. Your local edits are safe.';
    }
    if (code == null && error.type == DioExceptionType.connectionTimeout) {
      return 'Timed out connecting to GitHub. Check your connection, then try again. Your local edits are safe.';
    }
    if (code == null &&
        (error.type == DioExceptionType.sendTimeout ||
            error.type == DioExceptionType.receiveTimeout)) {
      return 'GitHub sync timed out. Check your connection, then try again. Your local edits are safe.';
    }
    if (code == 409) {
      return 'GitHub rejected a concurrent change; pull again to preserve both versions.';
    }
    if (code == 422) {
      if (responseMessage.contains('protected') ||
          responseMessage.contains('branch rule') ||
          responseMessage.contains('ruleset')) {
        return 'GitHub branch protection prevents direct sync commits. Allow this token to push to the branch or choose an unprotected branch.';
      }
      if (responseMessage.contains('fast forward') ||
          responseMessage.contains('reference update')) {
        return 'GitHub rejected a concurrent change; pull again to preserve both versions.';
      }
      return responseDetail.isEmpty
          ? 'GitHub rejected this branch update. Your local edits are safe.'
          : 'GitHub rejected this branch update: $responseDetail';
    }
    return switch (code) {
      401 => 'GitHub token is invalid or expired.',
      403 => 'GitHub denied access. Check the token\'s Contents permission.',
      404 => 'GitHub repository or branch was not found.',
      _ => 'GitHub sync failed${code == null ? '' : ' ($code)'}.',
    };
  }
}
