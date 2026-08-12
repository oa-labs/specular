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
    'does not create a conflict for a generated-summary-only difference',
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
      final remoteContent = note.rawMarkdown;
      await repository.markSynced(note, 'outdated-blob');
      await repository.updateSummary(
        (await repository.get(note.id))!,
        'Generated checklist summary',
      );
      final github = _FakeGitHub(path: note.path, content: remoteContent);
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
      expect((await repository.get(note.id))!.isDirty, isFalse);
      expect(
        (await repository.watchNotes().first).where((note) => note.isConflict),
        isEmpty,
      );
    },
  );

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

  test(
    'retries a rejected ref update against a fresh remote snapshot',
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
        rejectFirstRefUpdate: true,
      );
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
      expect(github.refUpdates, 2);
      expect(github.commitCreates, 2);
      expect((await repository.get(note.id))!.isDirty, isFalse);
    },
  );

  test(
    'does not re-upload changes when branch protection rejects a ref',
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
        refUpdateErrorMessage:
            'Protected branch update failed for refs/heads/main.',
      );
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

      expect(result.isSuccess, isFalse);
      expect(result.message, contains('branch protection'));
      expect(github.refUpdates, 1);
      expect(github.commitCreates, 1);
      expect((await repository.get(note.id))!.isDirty, isTrue);
    },
  );

  test(
    'reports GitHub rate-limit reset time without risking local edits',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'specular-github-test-',
      );
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(() async {
        await database.close();
        await root.delete(recursive: true);
      });

      final result = await GitHubSyncEngine(
        NoteRepository(database, Directory('${root.path}/notes')),
        const FlutterSecureStorage(),
        dio: Dio()
          ..httpClientAdapter = _ErrorAdapter(
            statusCode: 403,
            body: {'message': 'API rate limit exceeded'},
            headers: const {
              'x-ratelimit-remaining': ['0'],
              'x-ratelimit-reset': ['1786572000'],
            },
          ),
        settingsLoader: () async => const GitHubSettings(
          token: 'test-token',
          owner: 'owner',
          repo: 'notes',
        ),
      ).sync();

      expect(result.isSuccess, isFalse);
      expect(result.message, contains('GitHub API rate limit reached'));
      expect(result.message, contains('Resets at'));
      expect(result.message, contains('local edits are safe'));
    },
  );

  test('uses the cached remote head to skip an unchanged tree scan', () async {
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
    final github = _FakeGitHub(path: note.path, content: note.rawMarkdown);
    final cache = <String, String>{};
    addTearDown(() async {
      await database.close();
      await root.delete(recursive: true);
    });

    final engine = GitHubSyncEngine(
      repository,
      const FlutterSecureStorage(),
      dio: Dio()..httpClientAdapter = github.adapter,
      settingsLoader: () async => const GitHubSettings(
        token: 'test-token',
        owner: 'owner',
        repo: 'notes',
      ),
      cacheRead: (key) async => cache[key],
      cacheWrite: (key, value) async => cache[key] = value,
    );

    expect((await engine.sync()).isSuccess, isTrue);
    expect((await engine.sync()).isSuccess, isTrue);

    expect(github.repositoryReads, 1);
    expect(github.refReads, 2);
    expect(github.treeReads, 1);
  });

  test('uses GitHub compare for a small fast-forward remote update', () async {
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
    final github = _FakeGitHub(path: note.path, content: note.rawMarkdown);
    final cache = <String, String>{};
    addTearDown(() async {
      await database.close();
      await root.delete(recursive: true);
    });
    final engine = GitHubSyncEngine(
      repository,
      const FlutterSecureStorage(),
      dio: Dio()..httpClientAdapter = github.adapter,
      settingsLoader: () async => const GitHubSettings(
        token: 'test-token',
        owner: 'owner',
        repo: 'notes',
      ),
      cacheRead: (key) async => cache[key],
      cacheWrite: (key, value) async => cache[key] = value,
    );
    expect((await engine.sync()).isSuccess, isTrue);

    github.advance(note.rawMarkdown.replaceFirst('Ship', 'Done'));
    expect((await engine.sync()).isSuccess, isTrue);

    expect(github.compareRequests, 1);
    expect(github.treeReads, 1);
    expect((await repository.get(note.id))!.body, contains('Done'));
  });

  test(
    'a full sync reconciles clean conflict copies when the head is cached',
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
      final github = _FakeGitHub(path: note.path, content: note.rawMarkdown);
      final cache = <String, String>{};
      addTearDown(() async {
        await database.close();
        await root.delete(recursive: true);
      });
      final engine = GitHubSyncEngine(
        repository,
        const FlutterSecureStorage(),
        dio: Dio()..httpClientAdapter = github.adapter,
        settingsLoader: () async => const GitHubSettings(
          token: 'test-token',
          owner: 'owner',
          repo: 'notes',
        ),
        cacheRead: (key) async => cache[key],
        cacheWrite: (key, value) async => cache[key] = value,
      );
      expect((await engine.sync()).isSuccess, isTrue);
      await repository.preserveConflict((await repository.get(note.id))!);
      final conflict = (await repository.watchNotes().first).singleWhere(
        (candidate) => candidate.isConflict,
      );
      await repository.markSynced(conflict, 'conflict-blob');

      expect((await engine.sync(forceFullRemoteScan: true)).isSuccess, isTrue);
      expect(await repository.get(conflict.id), isNull);
      expect(github.treeReads, 2);
    },
  );

  test(
    'treats deletion of an already-absent remote note as complete',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'specular-github-test-',
      );
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      final repository = NoteRepository(
        database,
        Directory('${root.path}/notes'),
      );
      final remoteNote = await repository.create(
        title: 'Remote note',
        body: 'Already published',
      );
      await repository.markSynced(remoteNote, 'base-blob');
      final github = _FakeGitHub(
        path: remoteNote.path,
        content: remoteNote.rawMarkdown,
      );
      final cache = <String, String>{};
      addTearDown(() async {
        await database.close();
        await root.delete(recursive: true);
      });
      final engine = GitHubSyncEngine(
        repository,
        const FlutterSecureStorage(),
        dio: Dio()..httpClientAdapter = github.adapter,
        settingsLoader: () async => const GitHubSettings(
          token: 'test-token',
          owner: 'owner',
          repo: 'notes',
        ),
        cacheRead: (key) async => cache[key],
        cacheWrite: (key, value) async => cache[key] = value,
      );
      expect((await engine.sync()).isSuccess, isTrue);

      final temporary = await repository.create(
        title: 'Temporary conflict copy',
        body: 'Never published',
      );
      await repository.delete(temporary);
      expect((await engine.sync()).isSuccess, isTrue);

      expect(await repository.get(temporary.id), isNull);
      expect(github.treeCreates, 0);
      expect(github.commitCreates, 0);
    },
  );

  test('identifies GitHub DNS failures', () async {
    final root = await Directory.systemTemp.createTemp('specular-github-test-');
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(() async {
      await database.close();
      await root.delete(recursive: true);
    });

    final result = await GitHubSyncEngine(
      NoteRepository(database, Directory('${root.path}/notes')),
      const FlutterSecureStorage(),
      dio: Dio()..httpClientAdapter = const _DnsErrorAdapter(),
      settingsLoader: () async => const GitHubSettings(
        token: 'test-token',
        owner: 'owner',
        repo: 'notes',
      ),
    ).sync();

    expect(result.isSuccess, isFalse);
    expect(result.message, contains('GitHub DNS lookup failed'));
  });

  test('explains when branch protection blocks a sync', () async {
    final root = await Directory.systemTemp.createTemp('specular-github-test-');
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(() async {
      await database.close();
      await root.delete(recursive: true);
    });

    final result = await GitHubSyncEngine(
      NoteRepository(database, Directory('${root.path}/notes')),
      const FlutterSecureStorage(),
      dio: Dio()
        ..httpClientAdapter = _ErrorAdapter(
          statusCode: 422,
          body: const {
            'message': 'Protected branch update failed for refs/heads/main.',
          },
          headers: const {},
        ),
      settingsLoader: () async => const GitHubSettings(
        token: 'test-token',
        owner: 'owner',
        repo: 'notes',
      ),
    ).sync();

    expect(result.isSuccess, isFalse);
    expect(result.message, contains('branch protection'));
  });
}

class _FakeGitHub {
  _FakeGitHub({
    required this.path,
    required this.content,
    this.pauseFirstRepositoryRead = false,
    this.rejectFirstRefUpdate = false,
    this.refUpdateErrorMessage,
  });

  final String path;
  final String content;
  final bool pauseFirstRepositoryRead;
  final bool rejectFirstRefUpdate;
  final String? refUpdateErrorMessage;
  final _firstRead = Completer<void>();
  final _resume = Completer<void>();
  var _paused = false;
  var _refUpdateRejected = false;
  var _remoteAdvanced = false;
  String? _changedContent;
  var refUpdates = 0;
  var treeCreates = 0;
  var commitCreates = 0;
  var repositoryReads = 0;
  var refReads = 0;
  var treeReads = 0;
  var compareRequests = 0;
  final contentsApiRequests = <String>[];
  final blobRequests = <String>[];

  Future<void> get firstRepositoryRead => _firstRead.future;
  late final HttpClientAdapter adapter = _FakeAdapter(this);

  void resumeFirstRepositoryRead() => _resume.complete();

  void advance(String changedContent) {
    _remoteAdvanced = true;
    _changedContent = changedContent;
  }

  Future<ResponseBody> handle(RequestOptions request) async {
    if (pauseFirstRepositoryRead &&
        !_paused &&
        request.path == '/repos/owner/notes') {
      _paused = true;
      _firstRead.complete();
      await _resume.future;
    }
    final requestPath = request.path;
    if (requestPath.contains('/contents/')) {
      contentsApiRequests.add(requestPath);
    }
    if (requestPath.contains('/git/blobs/')) blobRequests.add(requestPath);
    if (request.method == 'GET' && requestPath == '/repos/owner/notes') {
      repositoryReads++;
    }
    if (request.method == 'GET' &&
        requestPath == '/repos/owner/notes/git/ref/heads/main') {
      refReads++;
    }
    if (request.method == 'GET' &&
        requestPath == '/repos/owner/notes/git/trees/tree-1') {
      treeReads++;
    }
    if (request.method == 'GET' && requestPath.contains('/compare/')) {
      compareRequests++;
    }
    var statusCode = 200;
    final response = switch ((request.method, requestPath)) {
      ('GET', '/repos/owner/notes') => {'default_branch': 'main'},
      ('GET', '/repos/owner/notes/git/ref/heads/main') => {
        'object': {'sha': _remoteAdvanced ? 'head-2' : 'head-1'},
      },
      ('GET', '/repos/owner/notes/git/commits/head-1') => {
        'tree': {'sha': 'tree-1'},
      },
      ('GET', '/repos/owner/notes/git/commits/head-2') => {
        'tree': {'sha': 'tree-2'},
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
      ('GET', '/repos/owner/notes/git/blobs/changed-blob') => {
        'content': base64Encode(utf8.encode(_changedContent ?? content)),
      },
      ('GET', '/repos/owner/notes/compare/head-1...head-2') => {
        'status': 'ahead',
        'files': [
          {'filename': path, 'status': 'modified', 'sha': 'changed-blob'},
        ],
      },
      ('POST', '/repos/owner/notes/git/blobs') => {'sha': 'new-blob'},
      ('POST', '/repos/owner/notes/git/trees') => () {
        treeCreates++;
        return {'sha': 'tree-2'};
      }(),
      ('POST', '/repos/owner/notes/git/commits') => () {
        commitCreates++;
        return {'sha': 'commit-2'};
      }(),
      ('PATCH', '/repos/owner/notes/git/refs/heads/main') => () {
        refUpdates++;
        if (refUpdateErrorMessage != null) {
          statusCode = 422;
          return {'message': refUpdateErrorMessage};
        }
        if (rejectFirstRefUpdate && !_refUpdateRejected) {
          _refUpdateRejected = true;
          statusCode = 422;
          return {'message': 'Reference update failed'};
        }
        return {'ref': 'refs/heads/main'};
      }(),
      _ => {'message': 'Unexpected $requestPath'},
    };
    return ResponseBody.fromString(
      jsonEncode(response),
      response['message'] == null
          ? statusCode
          : statusCode == 200
          ? 404
          : statusCode,
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

class _ErrorAdapter implements HttpClientAdapter {
  const _ErrorAdapter({
    required this.statusCode,
    required this.body,
    required this.headers,
  });

  final int statusCode;
  final Map<String, String> body;
  final Map<String, List<String>> headers;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    jsonEncode(body),
    statusCode,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
      ...headers,
    },
  );

  @override
  void close({bool force = false}) {}
}

class _DnsErrorAdapter implements HttpClientAdapter {
  const _DnsErrorAdapter();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) => throw DioException(
    requestOptions: options,
    type: DioExceptionType.connectionError,
    error: const SocketException('Failed host lookup: api.github.com'),
  );

  @override
  void close({bool force = false}) {}
}
