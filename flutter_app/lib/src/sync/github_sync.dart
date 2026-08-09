import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../data/note_repository.dart';
import '../domain/markdown.dart';

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

class GitHubSyncEngine {
  GitHubSyncEngine(this._repository, this._storage, {Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: 'https://api.github.com',
              headers: const {
                'Accept': 'application/vnd.github+json',
                'X-GitHub-Api-Version': '2022-11-28',
              },
            ),
          );

  final NoteRepository _repository;
  final FlutterSecureStorage _storage;
  final Dio _dio;
  Future<void> _tail = Future.value();

  Future<SyncResult> sync() => _serialized(() async {
    final settings = await GitHubSettings.load(_storage);
    if (settings == null) return const SyncResult.notConfigured();
    try {
      final branch = await _pull(settings);
      await _push(settings, branch);
      return const SyncResult.success('Synced with GitHub');
    } on DioException catch (error) {
      return SyncResult.failure(_friendlyError(error), error);
    } catch (error) {
      return SyncResult.failure('Sync failed: $error', error);
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
      final tree = await _dio.get<Map<String, dynamic>>(
        '/repos/${repository.owner}/${repository.name}/git/trees/$sha',
        queryParameters: const {'recursive': 1},
        options: _options(settings),
      );
      final entries = List<Map<String, dynamic>>.from(
        tree.data!['tree'] as List,
      );
      if (!entries.any(_isMarkdownNote)) {
        throw GitHubRepositoryException(
          '${repository.fullName} has no Markdown notes on ${repository.defaultBranch}.',
        );
      }
    } on DioException catch (error) {
      throw GitHubRepositoryException(_friendlyError(error));
    }
  }

  Future<String> _pull(GitHubSettings settings) async {
    final repository = await _dio.get<Map<String, dynamic>>(
      '/repos/${settings.owner}/${settings.repo}',
      options: _options(settings),
    );
    final branch = repository.data!['default_branch'] as String;
    final ref = await _dio.get<Map<String, dynamic>>(
      '/repos/${settings.owner}/${settings.repo}/git/ref/heads/$branch',
      options: _options(settings),
    );
    final sha = (ref.data!['object'] as Map<String, dynamic>)['sha'] as String;
    final treeResponse = await _dio.get<Map<String, dynamic>>(
      '/repos/${settings.owner}/${settings.repo}/git/trees/$sha',
      queryParameters: const {'recursive': 1},
      options: _options(settings),
    );
    if (treeResponse.data!['truncated'] == true)
      throw StateError(
        'Repository tree is too large for GitHub recursive sync.',
      );
    final entries = List<Map<String, dynamic>>.from(
      treeResponse.data!['tree'] as List,
    );
    final markdownEntries = entries.where(_isMarkdownNote).toList();
    for (final entry in markdownEntries) {
      final path = entry['path'] as String;
      final remoteSha = entry['sha'] as String;
      final local = await _repository.findByPath(path);
      if (local?.isPendingDeletion == true || local?.lastRemoteSha == remoteSha)
        continue;
      final content = await _content(settings, path, branch);
      final parsed = MarkdownContract.parse(content);
      final sameId = await _repository.get(
        MarkdownContract.identityFor(path, parsed.id),
      );
      if (local?.isDirty == true) await _repository.preserveConflict(local!);
      if (sameId != null && sameId.path != path && sameId.isDirty)
        await _repository.preserveConflict(sameId);
      await _repository.applyRemote(path: path, sha: remoteSha, raw: content);
    }
    await _repository.reconcileRemoteRemovals(
      markdownEntries.map((entry) => entry['path'] as String).toSet(),
    );
    for (final entry in entries.where(_isAttachment)) {
      final path = entry['path'] as String;
      final remoteSha = entry['sha'] as String;
      final local = await _repository.attachment(path);
      if (local?.lastRemoteSha == remoteSha || local?.isDirty == true) continue;
      await _repository.applyRemoteAttachment(
        path: path,
        sha: remoteSha,
        bytes: await _bytes(settings, path, branch),
        mimeType: _mimeFor(path),
      );
    }
    return branch;
  }

  Future<void> _push(GitHubSettings settings, String branch) async {
    // Markdown never references a binary that has not been uploaded yet.
    for (final attachment in await _repository.dirtyAttachments()) {
      final bytes = await _repository.attachmentBytes(attachment.path);
      if (bytes == null) continue;
      final response = await _dio.put<Map<String, dynamic>>(
        '/repos/${settings.owner}/${settings.repo}/contents/${attachment.path}',
        data: {
          'message': 'Update attachment ${attachment.path.split('/').last}',
          'content': base64Encode(bytes),
          if (attachment.lastRemoteSha != null) 'sha': attachment.lastRemoteSha,
          'branch': branch,
        },
        options: _options(settings),
      );
      final content = response.data?['content'] as Map<String, dynamic>?;
      await _repository.markAttachmentSynced(
        attachment.path,
        content?['sha'] as String? ?? attachment.lastRemoteSha ?? '',
      );
    }
    for (final note in await _repository.dirtyNotes()) {
      if (note.isPendingDeletion) {
        if (note.lastRemoteSha != null) {
          try {
            await _dio.delete<void>(
              '/repos/${settings.owner}/${settings.repo}/contents/${note.path}',
              data: {
                'message': 'Delete ${note.title}',
                'sha': note.lastRemoteSha,
                'branch': branch,
              },
              options: _options(settings),
            );
          } on DioException catch (error) {
            // Another client may have completed the deletion already.
            if (error.response?.statusCode != 404) rethrow;
          }
        }
        await _repository.completeDeletion(note);
        continue;
      }
      final response = await _dio.put<Map<String, dynamic>>(
        '/repos/${settings.owner}/${settings.repo}/contents/${note.path}',
        data: {
          'message': 'Update ${note.title}',
          'content': base64Encode(utf8.encode(note.rawMarkdown)),
          if (note.lastRemoteSha != null) 'sha': note.lastRemoteSha,
          'branch': branch,
        },
        options: _options(settings),
      );
      final content = response.data?['content'] as Map<String, dynamic>?;
      if (note.pendingRenameFromPath != null &&
          note.pendingRenameFromSha != null) {
        await _dio.delete<void>(
          '/repos/${settings.owner}/${settings.repo}/contents/${note.pendingRenameFromPath}',
          data: {
            'message': 'Rename ${note.title}',
            'sha': note.pendingRenameFromSha,
            'branch': branch,
          },
          options: _options(settings),
        );
      }
      await _repository.markSynced(
        note,
        content?['sha'] as String? ?? note.lastRemoteSha ?? '',
      );
    }
  }

  Future<String> _content(
    GitHubSettings settings,
    String path,
    String branch,
  ) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/repos/${settings.owner}/${settings.repo}/contents/$path',
      queryParameters: {'ref': branch},
      options: _options(settings),
    );
    final content = response.data?['content'] as String?;
    if (content == null)
      throw StateError('GitHub returned no content for $path');
    return utf8.decode(base64Decode(content.replaceAll('\n', '')));
  }

  Future<List<int>> _bytes(
    GitHubSettings settings,
    String path,
    String branch,
  ) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/repos/${settings.owner}/${settings.repo}/contents/$path',
      queryParameters: {'ref': branch},
      options: _options(settings),
    );
    final content = response.data?['content'] as String?;
    if (content == null)
      throw StateError('GitHub returned no content for $path');
    return base64Decode(content.replaceAll('\n', ''));
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
    return switch (code) {
      401 => 'GitHub token is invalid or expired.',
      403 => 'GitHub denied access or rate-limited this sync.',
      404 => 'GitHub repository or branch was not found.',
      409 || 422 =>
        'GitHub rejected a concurrent change; pull again to preserve both versions.',
      _ =>
        error.type == DioExceptionType.connectionError
            ? 'Network unavailable. Your local edits are safe.'
            : 'GitHub sync failed${code == null ? '' : ' ($code)'}.',
    };
  }
}
