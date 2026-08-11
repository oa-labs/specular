import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../data/note_repository.dart';
import '../domain/markdown.dart';

const initialSyncCompletedStorageKey = 'initial_sync_completed';

/// A concrete unit of sync work reported to the foreground UI. The totals are
/// based on the repository snapshot, rather than an indeterminate timer, so
/// first-time setup can say exactly how far through the import it is.
class SyncProgress {
  const SyncProgress({required this.message, this.completed, this.total});

  final String message;
  final int? completed;
  final int? total;
}

typedef SyncProgressCallback = void Function(SyncProgress progress);

class SyncResult {
  const SyncResult._(this.message, [this.error]);
  const SyncResult.success(String message) : this._(message);
  const SyncResult.failure(String message, Object error)
    : this._(message, error);
  const SyncResult.notConfigured() : this._('GitHub sync is not configured.');
  final String message;
  final Object? error;
  bool get isSuccess =>
      error == null && message != 'GitHub sync is not configured.';
}

class _ConcurrentRefUpdate implements Exception {
  const _ConcurrentRefUpdate(this.error);

  final DioException error;
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
  final Future<GitHubSettings?> Function() _settingsLoader;
  final Future<String?> Function(String key) _cacheRead;
  final Future<void> Function(String key, String value) _cacheWrite;
  final Dio _dio;
  Future<void> _tail = Future.value();

  static const _maxConcurrentChangeRetries = 1;

  Future<SyncResult> sync({
    SyncProgressCallback? onProgress,
  }) => _serialized(() async {
    onProgress?.call(const SyncProgress(message: 'Connecting to GitHub…'));
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
        final snapshot = await _pull(settings, onProgress: onProgress);
        try {
          final completedSnapshot = await _push(
            settings,
            snapshot,
            onProgress: onProgress,
          );
          await _saveCachedSnapshot(settings, completedSnapshot);
          onProgress?.call(const SyncProgress(message: 'Sync complete'));
          return const SyncResult.success('Synced with GitHub');
        } on _ConcurrentRefUpdate {
          if (attempt >= _maxConcurrentChangeRetries) rethrow;
          onProgress?.call(
            const SyncProgress(message: 'Remote changes detected; retrying…'),
          );
        }
      }
    } on _ConcurrentRefUpdate catch (conflict) {
      return SyncResult.failure(_friendlyError(conflict.error), conflict.error);
    } on DioException catch (error) {
      return SyncResult.failure(_friendlyError(error), error);
    } catch (error) {
      return SyncResult.failure('Sync failed: $error', error);
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

  /// Confirms that a selected repository contains Markdown before saving it.
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
      final entries = await _allTreeEntries(settings, treeSha);
      if (!entries.any(_isMarkdownNote)) {
        throw GitHubRepositoryException(
          '${repository.fullName} has no Markdown notes on ${repository.defaultBranch}.',
        );
      }
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

  Future<_RemoteSnapshot> _pull(
    GitHubSettings settings, {
    SyncProgressCallback? onProgress,
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
        cached.commitSha == commitSha) {
      onProgress?.call(const SyncProgress(message: 'Remote is up to date…'));
      return cached.toSnapshot();
    }
    final commit = await _dio.get<Map<String, dynamic>>(
      '/repos/${settings.owner}/${settings.repo}/git/commits/$commitSha',
      options: _options(settings),
    );
    final treeSha =
        (commit.data!['tree'] as Map<String, dynamic>)['sha'] as String;
    final entries = await _allTreeEntries(settings, treeSha);
    final markdownEntries = entries.where(_isMarkdownNote).toList();
    onProgress?.call(
      SyncProgress(
        message: 'Checking your notes…',
        completed: 0,
        total: markdownEntries.length,
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
        final content = await _blobContent(settings, remoteSha);
        final parsed = MarkdownContract.parse(content);
        final sameId = await _repository.get(
          MarkdownContract.identityFor(path, parsed.id),
        );
        if (local?.isDirty == true && local?.isPendingDeletion != true) {
          await _repository.preserveConflict(local!);
        }
        if (sameId != null && sameId.path != path && sameId.isDirty) {
          await _repository.preserveConflict(sameId);
        }
        await _repository.applyRemote(path: path, sha: remoteSha, raw: content);
      }
      onProgress?.call(
        SyncProgress(
          message: 'Checking your notes…',
          completed: index + 1,
          total: markdownEntries.length,
        ),
      );
    }
    await _repository.reconcileRemoteRemovals(
      markdownEntries.map((entry) => entry['path'] as String).toSet(),
    );
    final attachmentEntries = entries.where(_isAttachment).toList();
    onProgress?.call(
      SyncProgress(
        message: 'Checking attachments…',
        completed: 0,
        total: attachmentEntries.length,
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
        ),
      );
    }
    final snapshot = _RemoteSnapshot(
      branch: branch,
      commitSha: commitSha,
      treeSha: treeSha,
    );
    await _saveCachedSnapshot(settings, snapshot);
    return snapshot;
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
    final uploadCount = attachments.length + notes.length;
    onProgress?.call(
      SyncProgress(
        message: uploadCount == 0
            ? 'Finishing up…'
            : 'Uploading local changes…',
        completed: 0,
        total: uploadCount,
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
        ),
      );
    }
    for (final note in notes) {
      if (note.isPendingDeletion) {
        final path = note.pendingRenameFromPath ?? note.path;
        entries[path] = _treeDeletion(path);
        acknowledgements[note.id] = (revision: note.localRevision, sha: null);
        uploaded++;
        onProgress?.call(
          SyncProgress(
            message: 'Uploading local changes…',
            completed: uploaded,
            total: uploadCount,
          ),
        );
        continue;
      }
      final sha = await _createBlob(settings, utf8.encode(note.rawMarkdown));
      entries[note.path] = _treeBlob(note.path, sha);
      if (note.pendingRenameFromPath != null) {
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
        ),
      );
    }
    if (entries.isEmpty) return snapshot;

    onProgress?.call(const SyncProgress(message: 'Saving your changes…'));

    final tree = await _dio.post<Map<String, dynamic>>(
      '/repos/${settings.owner}/${settings.repo}/git/trees',
      data: {'base_tree': snapshot.treeSha, 'tree': entries.values.toList()},
      options: _options(settings),
    );
    final newTreeSha = tree.data?['sha'] as String?;
    if (newTreeSha == null) throw StateError('GitHub returned no tree SHA');
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
    try {
      await _dio.patch<void>(
        '/repos/${settings.owner}/${settings.repo}/git/refs/heads/${Uri.encodeComponent(snapshot.branch)}',
        data: {'sha': commitSha, 'force': false},
        options: _options(settings),
      );
    } on DioException catch (error) {
      final status = error.response?.statusCode;
      if (status == 409 || status == 422) {
        throw _ConcurrentRefUpdate(error);
      }
      rethrow;
    }
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
    return entry['type'] == 'blob' &&
        path.endsWith('.md') &&
        !path.endsWith('.reflect.md');
  }

  bool _isAttachment(Map<String, dynamic> entry) {
    final path = entry['path'] as String? ?? '';
    return entry['type'] == 'blob' &&
        (path.startsWith('attachments/') || path.startsWith('assets/')) &&
        !path.endsWith('.reflect.md');
  }

  String? _mimeFor(String path) => switch (path.toLowerCase().split('.').last) {
    'png' => 'image/png',
    'gif' => 'image/gif',
    'webp' => 'image/webp',
    'jpg' || 'jpeg' => 'image/jpeg',
    _ => null,
  };

  String _friendlyError(DioException error) {
    final code = error.response?.statusCode;
    final responseMessage = error.response?.data is Map
        ? (error.response?.data as Map)['message']?.toString().toLowerCase()
        : null;
    final rateLimitRemaining = error.response?.headers.value(
      'x-ratelimit-remaining',
    );
    final rateLimitReset = error.response?.headers.value('x-ratelimit-reset');
    final rateLimited =
        rateLimitRemaining == '0' ||
        responseMessage?.contains('rate limit') == true;
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
    return switch (code) {
      401 => 'GitHub token is invalid or expired.',
      403 => 'GitHub denied access. Check the token\'s Contents permission.',
      404 => 'GitHub repository or branch was not found.',
      409 || 422 =>
        'GitHub rejected a concurrent change; pull again to preserve both versions.',
      _ => 'GitHub sync failed${code == null ? '' : ' ($code)'}.',
    };
  }
}
