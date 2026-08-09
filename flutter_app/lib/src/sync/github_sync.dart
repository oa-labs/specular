import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../data/note_repository.dart';
import '../domain/markdown.dart';

class SyncResult {
  const SyncResult._(this.message, [this.error]);
  const SyncResult.success(String message) : this._(message);
  const SyncResult.failure(String message, Object error) : this._(message, error);
  const SyncResult.notConfigured() : this._('GitHub sync is not configured.');
  final String message;
  final Object? error;
  bool get isSuccess => error == null && message != 'GitHub sync is not configured.';
}

class GitHubSettings {
  const GitHubSettings({required this.token, required this.owner, required this.repo});
  final String token;
  final String owner;
  final String repo;

  static Future<GitHubSettings?> load(FlutterSecureStorage storage) async {
    final token = (await storage.read(key: 'github_token'))?.trim() ?? '';
    final owner = (await storage.read(key: 'repo_owner'))?.trim() ?? '';
    final repo = (await storage.read(key: 'repo_name'))?.trim() ?? '';
    return token.isEmpty || owner.isEmpty || repo.isEmpty ? null : GitHubSettings(token: token, owner: owner, repo: repo);
  }
}

class GitHubSyncEngine {
  GitHubSyncEngine(this._repository, this._storage)
      : _dio = Dio(
          BaseOptions(
            baseUrl: 'https://api.github.com',
            headers: const {'Accept': 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28'},
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
          await _pull(settings);
          await _push(settings);
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

  Options _options(GitHubSettings settings) => Options(headers: {'Authorization': 'Bearer ${settings.token}'});

  Future<void> _pull(GitHubSettings settings) async {
    final repository = await _dio.get<Map<String, dynamic>>('/repos/${settings.owner}/${settings.repo}', options: _options(settings));
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
    if (treeResponse.data!['truncated'] == true) throw StateError('Repository tree is too large for GitHub recursive sync.');
    final entries = List<Map<String, dynamic>>.from(treeResponse.data!['tree'] as List);
    for (final entry in entries.where(_isMarkdownNote)) {
      final path = entry['path'] as String;
      final remoteSha = entry['sha'] as String;
      final local = await _repository.findByPath(path);
      if (local?.isPendingDeletion == true || local?.lastRemoteSha == remoteSha) continue;
      final content = await _content(settings, path, branch);
      final parsed = MarkdownContract.parse(content);
      final sameId = await _repository.get(MarkdownContract.identityFor(path, parsed.id));
      if (local?.isDirty == true) await _repository.preserveConflict(local!);
      if (sameId != null && sameId.path != path && sameId.isDirty) await _repository.preserveConflict(sameId);
      await _repository.applyRemote(path: path, sha: remoteSha, raw: content);
    }
  }

  Future<void> _push(GitHubSettings settings) async {
    for (final note in await _repository.dirtyNotes()) {
      if (note.isPendingDeletion) {
        if (note.lastRemoteSha != null) {
          await _dio.delete<void>(
            '/repos/${settings.owner}/${settings.repo}/contents/${note.path}',
            data: {'message': 'Delete ${note.title}', 'sha': note.lastRemoteSha, 'branch': 'main'},
            options: _options(settings),
          );
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
          'branch': 'main',
        },
        options: _options(settings),
      );
      final content = response.data?['content'] as Map<String, dynamic>?;
      await _repository.markSynced(note, content?['sha'] as String? ?? note.lastRemoteSha ?? '');
    }
  }

  Future<String> _content(GitHubSettings settings, String path, String branch) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/repos/${settings.owner}/${settings.repo}/contents/$path',
      queryParameters: {'ref': branch},
      options: _options(settings),
    );
    final content = response.data?['content'] as String?;
    if (content == null) throw StateError('GitHub returned no content for $path');
    return utf8.decode(base64Decode(content.replaceAll('\n', '')));
  }

  bool _isMarkdownNote(Map<String, dynamic> entry) {
    final path = entry['path'] as String? ?? '';
    return entry['type'] == 'blob' && path.endsWith('.md') && !path.endsWith('.reflect.md');
  }

  String _friendlyError(DioException error) {
    final code = error.response?.statusCode;
    return switch (code) {
      401 => 'GitHub token is invalid or expired.',
      403 => 'GitHub denied access or rate-limited this sync.',
      404 => 'GitHub repository or branch was not found.',
      409 || 422 => 'GitHub rejected a concurrent change; pull again to preserve both versions.',
      _ => error.type == DioExceptionType.connectionError ? 'Network unavailable. Your local edits are safe.' : 'GitHub sync failed${code == null ? '' : ' ($code)'}.',
    };
  }
}
