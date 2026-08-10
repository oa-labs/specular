import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:specular/src/data/app_database.dart';
import 'package:specular/src/data/note_repository.dart';
import 'package:specular/src/sync/github_sync.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('skips unchanged Markdown note blobs during pull', () async {
    final root = await Directory.systemTemp.createTemp('specular-github-test-');
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final repository = NoteRepository(
      database,
      Directory('${root.path}/notes'),
    );
    final note = await repository.create(
      title: 'Checklist',
      body: '+ [ ] Ship',
    );
    await repository.markSynced(note, 'base-blob');
    final before = await repository.get(note.id);
    final github = _FakeGitHub(path: note.path, content: note.rawMarkdown);
    addTearDown(() async {
      await database.close();
      await root.delete(recursive: true);
    });

    final result = await GitHubSyncEngine(
      repository,
      const FlutterSecureStorage(),
      dio: Dio()..httpClientAdapter = github.adapter,
      settingsLoader: () async => const GitHubSettings(
        token: 'test-token',
        owner: 'owner',
        repo: 'notes',
      ),
    ).sync();

    expect(result.isSuccess, isTrue);
    expect(github.blobRequests, isEmpty);
    expect(github.commitCreates, 0);
    expect(github.refUpdates, 0);
    expect((await repository.get(note.id))!.updatedAt, before!.updatedAt);
  });

  test(
    'overlapping syncs share a lease and publish one atomic commit',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'specular-github-test-',
      );
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      final repository = NoteRepository(
        database,
        Directory('${root.path}/notes'),
      );
      final note = await repository.create(
        title: 'Checklist',
        body: '+ [ ] Ship',
      );
      await repository.markSynced(note, 'base-blob');
      await repository.toggleTodo((await repository.watchTodos().first).single);
      final github = _FakeGitHub(
        path: note.path,
        content: note.rawMarkdown,
        pauseFirstRepositoryRead: true,
      );
      addTearDown(() async {
        await database.close();
        await root.delete(recursive: true);
      });

      GitHubSyncEngine engine() => GitHubSyncEngine(
        repository,
        const FlutterSecureStorage(),
        dio: Dio()..httpClientAdapter = github.adapter,
        settingsLoader: () async => const GitHubSettings(
          token: 'test-token',
          owner: 'owner',
          repo: 'notes',
        ),
      );

      final first = engine().sync();
      await github.firstRepositoryRead;
      final second = await engine().sync();
      expect(second.message, 'Another sync is already running.');

      github.resumeFirstRepositoryRead();
      expect((await first).isSuccess, isTrue);
      expect(github.refUpdates, 1);
      expect(github.commitCreates, 1);
      expect(github.contentsApiRequests, isEmpty);
      expect((await repository.get(note.id))!.isDirty, isFalse);
    },
  );
}

class _FakeGitHub {
  _FakeGitHub({
    required this.path,
    required this.content,
    this.pauseFirstRepositoryRead = false,
  });

  final String path;
  final String content;
  final bool pauseFirstRepositoryRead;
  final _firstRead = Completer<void>();
  final _resume = Completer<void>();
  var _paused = false;
  var refUpdates = 0;
  var commitCreates = 0;
  final contentsApiRequests = <String>[];
  final blobRequests = <String>[];

  Future<void> get firstRepositoryRead => _firstRead.future;
  late final HttpClientAdapter adapter = _FakeAdapter(this);

  void resumeFirstRepositoryRead() => _resume.complete();

  Future<ResponseBody> handle(RequestOptions request) async {
    if (pauseFirstRepositoryRead &&
        !_paused &&
        request.path == '/repos/owner/notes') {
      _paused = true;
      _firstRead.complete();
      await _resume.future;
    }
    final requestPath = request.path;
    if (requestPath.contains('/contents/'))
      contentsApiRequests.add(requestPath);
    if (requestPath.contains('/git/blobs/')) blobRequests.add(requestPath);
    final response = switch ((request.method, requestPath)) {
      ('GET', '/repos/owner/notes') => {'default_branch': 'main'},
      ('GET', '/repos/owner/notes/git/ref/heads/main') => {
        'object': {'sha': 'head-1'},
      },
      ('GET', '/repos/owner/notes/git/commits/head-1') => {
        'tree': {'sha': 'tree-1'},
      },
      ('GET', '/repos/owner/notes/git/trees/tree-1') => {
        'truncated': false,
        'tree': [
          {'type': 'blob', 'path': path, 'sha': 'base-blob'},
        ],
      },
      ('GET', '/repos/owner/notes/git/blobs/base-blob') => {
        'content': base64Encode(utf8.encode(content)),
      },
      ('POST', '/repos/owner/notes/git/blobs') => {'sha': 'new-blob'},
      ('POST', '/repos/owner/notes/git/trees') => {'sha': 'tree-2'},
      ('POST', '/repos/owner/notes/git/commits') => () {
        commitCreates++;
        return {'sha': 'commit-2'};
      }(),
      ('PATCH', '/repos/owner/notes/git/refs/heads/main') => () {
        refUpdates++;
        return {'ref': 'refs/heads/main'};
      }(),
      _ => {'message': 'Unexpected $requestPath'},
    };
    return ResponseBody.fromString(
      jsonEncode(response),
      response['message'] == null ? 200 : 404,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this._github);

  final _FakeGitHub _github;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) => _github.handle(options);

  @override
  void close({bool force = false}) {}
}
