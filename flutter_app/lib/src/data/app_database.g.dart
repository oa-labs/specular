// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $NoteRowsTable extends NoteRows with TableInfo<$NoteRowsTable, NoteRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $NoteRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pathMeta = const VerificationMeta('path');
  @override
  late final GeneratedColumn<String> path = GeneratedColumn<String>(
    'path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _rawMarkdownMeta = const VerificationMeta(
    'rawMarkdown',
  );
  @override
  late final GeneratedColumn<String> rawMarkdown = GeneratedColumn<String>(
    'rawMarkdown',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bodyMeta = const VerificationMeta('body');
  @override
  late final GeneratedColumn<String> body = GeneratedColumn<String>(
    'body',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _aliasesMeta = const VerificationMeta(
    'aliases',
  );
  @override
  late final GeneratedColumn<String> aliases = GeneratedColumn<String>(
    'aliases',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _summaryMeta = const VerificationMeta(
    'summary',
  );
  @override
  late final GeneratedColumn<String> summary = GeneratedColumn<String>(
    'summary',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isDailyMeta = const VerificationMeta(
    'isDaily',
  );
  @override
  late final GeneratedColumn<bool> isDaily = GeneratedColumn<bool>(
    'isDaily',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("isDaily" IN (0, 1))',
    ),
  );
  static const VerificationMeta _isPinnedMeta = const VerificationMeta(
    'isPinned',
  );
  @override
  late final GeneratedColumn<bool> isPinned = GeneratedColumn<bool>(
    'isPinned',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("isPinned" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _lastRemoteShaMeta = const VerificationMeta(
    'lastRemoteSha',
  );
  @override
  late final GeneratedColumn<String> lastRemoteSha = GeneratedColumn<String>(
    'lastRemoteSha',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isDirtyMeta = const VerificationMeta(
    'isDirty',
  );
  @override
  late final GeneratedColumn<bool> isDirty = GeneratedColumn<bool>(
    'isDirty',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("isDirty" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _isPendingDeletionMeta = const VerificationMeta(
    'isPendingDeletion',
  );
  @override
  late final GeneratedColumn<bool> isPendingDeletion = GeneratedColumn<bool>(
    'isPendingDeletion',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("isPendingDeletion" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _pendingRenameFromPathMeta =
      const VerificationMeta('pendingRenameFromPath');
  @override
  late final GeneratedColumn<String> pendingRenameFromPath =
      GeneratedColumn<String>(
        'pendingRenameFromPath',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _pendingRenameFromShaMeta =
      const VerificationMeta('pendingRenameFromSha');
  @override
  late final GeneratedColumn<String> pendingRenameFromSha =
      GeneratedColumn<String>(
        'pendingRenameFromSha',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _isConflictMeta = const VerificationMeta(
    'isConflict',
  );
  @override
  late final GeneratedColumn<bool> isConflict = GeneratedColumn<bool>(
    'isConflict',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("isConflict" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _localRevisionMeta = const VerificationMeta(
    'localRevision',
  );
  @override
  late final GeneratedColumn<int> localRevision = GeneratedColumn<int>(
    'localRevision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updatedAt',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    title,
    path,
    rawMarkdown,
    body,
    aliases,
    summary,
    isDaily,
    isPinned,
    lastRemoteSha,
    isDirty,
    isPendingDeletion,
    pendingRenameFromPath,
    pendingRenameFromSha,
    isConflict,
    localRevision,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'notes';
  @override
  VerificationContext validateIntegrity(
    Insertable<NoteRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('path')) {
      context.handle(
        _pathMeta,
        path.isAcceptableOrUnknown(data['path']!, _pathMeta),
      );
    } else if (isInserting) {
      context.missing(_pathMeta);
    }
    if (data.containsKey('rawMarkdown')) {
      context.handle(
        _rawMarkdownMeta,
        rawMarkdown.isAcceptableOrUnknown(
          data['rawMarkdown']!,
          _rawMarkdownMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_rawMarkdownMeta);
    }
    if (data.containsKey('body')) {
      context.handle(
        _bodyMeta,
        body.isAcceptableOrUnknown(data['body']!, _bodyMeta),
      );
    } else if (isInserting) {
      context.missing(_bodyMeta);
    }
    if (data.containsKey('aliases')) {
      context.handle(
        _aliasesMeta,
        aliases.isAcceptableOrUnknown(data['aliases']!, _aliasesMeta),
      );
    } else if (isInserting) {
      context.missing(_aliasesMeta);
    }
    if (data.containsKey('summary')) {
      context.handle(
        _summaryMeta,
        summary.isAcceptableOrUnknown(data['summary']!, _summaryMeta),
      );
    }
    if (data.containsKey('isDaily')) {
      context.handle(
        _isDailyMeta,
        isDaily.isAcceptableOrUnknown(data['isDaily']!, _isDailyMeta),
      );
    } else if (isInserting) {
      context.missing(_isDailyMeta);
    }
    if (data.containsKey('isPinned')) {
      context.handle(
        _isPinnedMeta,
        isPinned.isAcceptableOrUnknown(data['isPinned']!, _isPinnedMeta),
      );
    }
    if (data.containsKey('lastRemoteSha')) {
      context.handle(
        _lastRemoteShaMeta,
        lastRemoteSha.isAcceptableOrUnknown(
          data['lastRemoteSha']!,
          _lastRemoteShaMeta,
        ),
      );
    }
    if (data.containsKey('isDirty')) {
      context.handle(
        _isDirtyMeta,
        isDirty.isAcceptableOrUnknown(data['isDirty']!, _isDirtyMeta),
      );
    }
    if (data.containsKey('isPendingDeletion')) {
      context.handle(
        _isPendingDeletionMeta,
        isPendingDeletion.isAcceptableOrUnknown(
          data['isPendingDeletion']!,
          _isPendingDeletionMeta,
        ),
      );
    }
    if (data.containsKey('pendingRenameFromPath')) {
      context.handle(
        _pendingRenameFromPathMeta,
        pendingRenameFromPath.isAcceptableOrUnknown(
          data['pendingRenameFromPath']!,
          _pendingRenameFromPathMeta,
        ),
      );
    }
    if (data.containsKey('pendingRenameFromSha')) {
      context.handle(
        _pendingRenameFromShaMeta,
        pendingRenameFromSha.isAcceptableOrUnknown(
          data['pendingRenameFromSha']!,
          _pendingRenameFromShaMeta,
        ),
      );
    }
    if (data.containsKey('isConflict')) {
      context.handle(
        _isConflictMeta,
        isConflict.isAcceptableOrUnknown(data['isConflict']!, _isConflictMeta),
      );
    }
    if (data.containsKey('localRevision')) {
      context.handle(
        _localRevisionMeta,
        localRevision.isAcceptableOrUnknown(
          data['localRevision']!,
          _localRevisionMeta,
        ),
      );
    }
    if (data.containsKey('updatedAt')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updatedAt']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  NoteRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return NoteRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      path: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}path'],
      )!,
      rawMarkdown: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}rawMarkdown'],
      )!,
      body: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body'],
      )!,
      aliases: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}aliases'],
      )!,
      summary: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}summary'],
      ),
      isDaily: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}isDaily'],
      )!,
      isPinned: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}isPinned'],
      )!,
      lastRemoteSha: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}lastRemoteSha'],
      ),
      isDirty: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}isDirty'],
      )!,
      isPendingDeletion: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}isPendingDeletion'],
      )!,
      pendingRenameFromPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pendingRenameFromPath'],
      ),
      pendingRenameFromSha: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pendingRenameFromSha'],
      ),
      isConflict: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}isConflict'],
      )!,
      localRevision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}localRevision'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updatedAt'],
      )!,
    );
  }

  @override
  $NoteRowsTable createAlias(String alias) {
    return $NoteRowsTable(attachedDatabase, alias);
  }
}

class NoteRow extends DataClass implements Insertable<NoteRow> {
  final String id;
  final String title;
  final String path;
  final String rawMarkdown;
  final String body;
  final String aliases;
  final String? summary;
  final bool isDaily;
  final bool isPinned;
  final String? lastRemoteSha;
  final bool isDirty;
  final bool isPendingDeletion;
  final String? pendingRenameFromPath;
  final String? pendingRenameFromSha;
  final bool isConflict;

  /// Incremented for every local mutation.  Remote acknowledgements must only
  /// clear dirty state when they acknowledge this exact revision.
  final int localRevision;
  final int updatedAt;
  const NoteRow({
    required this.id,
    required this.title,
    required this.path,
    required this.rawMarkdown,
    required this.body,
    required this.aliases,
    this.summary,
    required this.isDaily,
    required this.isPinned,
    this.lastRemoteSha,
    required this.isDirty,
    required this.isPendingDeletion,
    this.pendingRenameFromPath,
    this.pendingRenameFromSha,
    required this.isConflict,
    required this.localRevision,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['title'] = Variable<String>(title);
    map['path'] = Variable<String>(path);
    map['rawMarkdown'] = Variable<String>(rawMarkdown);
    map['body'] = Variable<String>(body);
    map['aliases'] = Variable<String>(aliases);
    if (!nullToAbsent || summary != null) {
      map['summary'] = Variable<String>(summary);
    }
    map['isDaily'] = Variable<bool>(isDaily);
    map['isPinned'] = Variable<bool>(isPinned);
    if (!nullToAbsent || lastRemoteSha != null) {
      map['lastRemoteSha'] = Variable<String>(lastRemoteSha);
    }
    map['isDirty'] = Variable<bool>(isDirty);
    map['isPendingDeletion'] = Variable<bool>(isPendingDeletion);
    if (!nullToAbsent || pendingRenameFromPath != null) {
      map['pendingRenameFromPath'] = Variable<String>(pendingRenameFromPath);
    }
    if (!nullToAbsent || pendingRenameFromSha != null) {
      map['pendingRenameFromSha'] = Variable<String>(pendingRenameFromSha);
    }
    map['isConflict'] = Variable<bool>(isConflict);
    map['localRevision'] = Variable<int>(localRevision);
    map['updatedAt'] = Variable<int>(updatedAt);
    return map;
  }

  NoteRowsCompanion toCompanion(bool nullToAbsent) {
    return NoteRowsCompanion(
      id: Value(id),
      title: Value(title),
      path: Value(path),
      rawMarkdown: Value(rawMarkdown),
      body: Value(body),
      aliases: Value(aliases),
      summary: summary == null && nullToAbsent
          ? const Value.absent()
          : Value(summary),
      isDaily: Value(isDaily),
      isPinned: Value(isPinned),
      lastRemoteSha: lastRemoteSha == null && nullToAbsent
          ? const Value.absent()
          : Value(lastRemoteSha),
      isDirty: Value(isDirty),
      isPendingDeletion: Value(isPendingDeletion),
      pendingRenameFromPath: pendingRenameFromPath == null && nullToAbsent
          ? const Value.absent()
          : Value(pendingRenameFromPath),
      pendingRenameFromSha: pendingRenameFromSha == null && nullToAbsent
          ? const Value.absent()
          : Value(pendingRenameFromSha),
      isConflict: Value(isConflict),
      localRevision: Value(localRevision),
      updatedAt: Value(updatedAt),
    );
  }

  factory NoteRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return NoteRow(
      id: serializer.fromJson<String>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      path: serializer.fromJson<String>(json['path']),
      rawMarkdown: serializer.fromJson<String>(json['rawMarkdown']),
      body: serializer.fromJson<String>(json['body']),
      aliases: serializer.fromJson<String>(json['aliases']),
      summary: serializer.fromJson<String?>(json['summary']),
      isDaily: serializer.fromJson<bool>(json['isDaily']),
      isPinned: serializer.fromJson<bool>(json['isPinned']),
      lastRemoteSha: serializer.fromJson<String?>(json['lastRemoteSha']),
      isDirty: serializer.fromJson<bool>(json['isDirty']),
      isPendingDeletion: serializer.fromJson<bool>(json['isPendingDeletion']),
      pendingRenameFromPath: serializer.fromJson<String?>(
        json['pendingRenameFromPath'],
      ),
      pendingRenameFromSha: serializer.fromJson<String?>(
        json['pendingRenameFromSha'],
      ),
      isConflict: serializer.fromJson<bool>(json['isConflict']),
      localRevision: serializer.fromJson<int>(json['localRevision']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'title': serializer.toJson<String>(title),
      'path': serializer.toJson<String>(path),
      'rawMarkdown': serializer.toJson<String>(rawMarkdown),
      'body': serializer.toJson<String>(body),
      'aliases': serializer.toJson<String>(aliases),
      'summary': serializer.toJson<String?>(summary),
      'isDaily': serializer.toJson<bool>(isDaily),
      'isPinned': serializer.toJson<bool>(isPinned),
      'lastRemoteSha': serializer.toJson<String?>(lastRemoteSha),
      'isDirty': serializer.toJson<bool>(isDirty),
      'isPendingDeletion': serializer.toJson<bool>(isPendingDeletion),
      'pendingRenameFromPath': serializer.toJson<String?>(
        pendingRenameFromPath,
      ),
      'pendingRenameFromSha': serializer.toJson<String?>(pendingRenameFromSha),
      'isConflict': serializer.toJson<bool>(isConflict),
      'localRevision': serializer.toJson<int>(localRevision),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  NoteRow copyWith({
    String? id,
    String? title,
    String? path,
    String? rawMarkdown,
    String? body,
    String? aliases,
    Value<String?> summary = const Value.absent(),
    bool? isDaily,
    bool? isPinned,
    Value<String?> lastRemoteSha = const Value.absent(),
    bool? isDirty,
    bool? isPendingDeletion,
    Value<String?> pendingRenameFromPath = const Value.absent(),
    Value<String?> pendingRenameFromSha = const Value.absent(),
    bool? isConflict,
    int? localRevision,
    int? updatedAt,
  }) => NoteRow(
    id: id ?? this.id,
    title: title ?? this.title,
    path: path ?? this.path,
    rawMarkdown: rawMarkdown ?? this.rawMarkdown,
    body: body ?? this.body,
    aliases: aliases ?? this.aliases,
    summary: summary.present ? summary.value : this.summary,
    isDaily: isDaily ?? this.isDaily,
    isPinned: isPinned ?? this.isPinned,
    lastRemoteSha: lastRemoteSha.present
        ? lastRemoteSha.value
        : this.lastRemoteSha,
    isDirty: isDirty ?? this.isDirty,
    isPendingDeletion: isPendingDeletion ?? this.isPendingDeletion,
    pendingRenameFromPath: pendingRenameFromPath.present
        ? pendingRenameFromPath.value
        : this.pendingRenameFromPath,
    pendingRenameFromSha: pendingRenameFromSha.present
        ? pendingRenameFromSha.value
        : this.pendingRenameFromSha,
    isConflict: isConflict ?? this.isConflict,
    localRevision: localRevision ?? this.localRevision,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  NoteRow copyWithCompanion(NoteRowsCompanion data) {
    return NoteRow(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      path: data.path.present ? data.path.value : this.path,
      rawMarkdown: data.rawMarkdown.present
          ? data.rawMarkdown.value
          : this.rawMarkdown,
      body: data.body.present ? data.body.value : this.body,
      aliases: data.aliases.present ? data.aliases.value : this.aliases,
      summary: data.summary.present ? data.summary.value : this.summary,
      isDaily: data.isDaily.present ? data.isDaily.value : this.isDaily,
      isPinned: data.isPinned.present ? data.isPinned.value : this.isPinned,
      lastRemoteSha: data.lastRemoteSha.present
          ? data.lastRemoteSha.value
          : this.lastRemoteSha,
      isDirty: data.isDirty.present ? data.isDirty.value : this.isDirty,
      isPendingDeletion: data.isPendingDeletion.present
          ? data.isPendingDeletion.value
          : this.isPendingDeletion,
      pendingRenameFromPath: data.pendingRenameFromPath.present
          ? data.pendingRenameFromPath.value
          : this.pendingRenameFromPath,
      pendingRenameFromSha: data.pendingRenameFromSha.present
          ? data.pendingRenameFromSha.value
          : this.pendingRenameFromSha,
      isConflict: data.isConflict.present
          ? data.isConflict.value
          : this.isConflict,
      localRevision: data.localRevision.present
          ? data.localRevision.value
          : this.localRevision,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('NoteRow(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('path: $path, ')
          ..write('rawMarkdown: $rawMarkdown, ')
          ..write('body: $body, ')
          ..write('aliases: $aliases, ')
          ..write('summary: $summary, ')
          ..write('isDaily: $isDaily, ')
          ..write('isPinned: $isPinned, ')
          ..write('lastRemoteSha: $lastRemoteSha, ')
          ..write('isDirty: $isDirty, ')
          ..write('isPendingDeletion: $isPendingDeletion, ')
          ..write('pendingRenameFromPath: $pendingRenameFromPath, ')
          ..write('pendingRenameFromSha: $pendingRenameFromSha, ')
          ..write('isConflict: $isConflict, ')
          ..write('localRevision: $localRevision, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    title,
    path,
    rawMarkdown,
    body,
    aliases,
    summary,
    isDaily,
    isPinned,
    lastRemoteSha,
    isDirty,
    isPendingDeletion,
    pendingRenameFromPath,
    pendingRenameFromSha,
    isConflict,
    localRevision,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NoteRow &&
          other.id == this.id &&
          other.title == this.title &&
          other.path == this.path &&
          other.rawMarkdown == this.rawMarkdown &&
          other.body == this.body &&
          other.aliases == this.aliases &&
          other.summary == this.summary &&
          other.isDaily == this.isDaily &&
          other.isPinned == this.isPinned &&
          other.lastRemoteSha == this.lastRemoteSha &&
          other.isDirty == this.isDirty &&
          other.isPendingDeletion == this.isPendingDeletion &&
          other.pendingRenameFromPath == this.pendingRenameFromPath &&
          other.pendingRenameFromSha == this.pendingRenameFromSha &&
          other.isConflict == this.isConflict &&
          other.localRevision == this.localRevision &&
          other.updatedAt == this.updatedAt);
}

class NoteRowsCompanion extends UpdateCompanion<NoteRow> {
  final Value<String> id;
  final Value<String> title;
  final Value<String> path;
  final Value<String> rawMarkdown;
  final Value<String> body;
  final Value<String> aliases;
  final Value<String?> summary;
  final Value<bool> isDaily;
  final Value<bool> isPinned;
  final Value<String?> lastRemoteSha;
  final Value<bool> isDirty;
  final Value<bool> isPendingDeletion;
  final Value<String?> pendingRenameFromPath;
  final Value<String?> pendingRenameFromSha;
  final Value<bool> isConflict;
  final Value<int> localRevision;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const NoteRowsCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.path = const Value.absent(),
    this.rawMarkdown = const Value.absent(),
    this.body = const Value.absent(),
    this.aliases = const Value.absent(),
    this.summary = const Value.absent(),
    this.isDaily = const Value.absent(),
    this.isPinned = const Value.absent(),
    this.lastRemoteSha = const Value.absent(),
    this.isDirty = const Value.absent(),
    this.isPendingDeletion = const Value.absent(),
    this.pendingRenameFromPath = const Value.absent(),
    this.pendingRenameFromSha = const Value.absent(),
    this.isConflict = const Value.absent(),
    this.localRevision = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  NoteRowsCompanion.insert({
    required String id,
    required String title,
    required String path,
    required String rawMarkdown,
    required String body,
    required String aliases,
    this.summary = const Value.absent(),
    required bool isDaily,
    this.isPinned = const Value.absent(),
    this.lastRemoteSha = const Value.absent(),
    this.isDirty = const Value.absent(),
    this.isPendingDeletion = const Value.absent(),
    this.pendingRenameFromPath = const Value.absent(),
    this.pendingRenameFromSha = const Value.absent(),
    this.isConflict = const Value.absent(),
    this.localRevision = const Value.absent(),
    required int updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       title = Value(title),
       path = Value(path),
       rawMarkdown = Value(rawMarkdown),
       body = Value(body),
       aliases = Value(aliases),
       isDaily = Value(isDaily),
       updatedAt = Value(updatedAt);
  static Insertable<NoteRow> custom({
    Expression<String>? id,
    Expression<String>? title,
    Expression<String>? path,
    Expression<String>? rawMarkdown,
    Expression<String>? body,
    Expression<String>? aliases,
    Expression<String>? summary,
    Expression<bool>? isDaily,
    Expression<bool>? isPinned,
    Expression<String>? lastRemoteSha,
    Expression<bool>? isDirty,
    Expression<bool>? isPendingDeletion,
    Expression<String>? pendingRenameFromPath,
    Expression<String>? pendingRenameFromSha,
    Expression<bool>? isConflict,
    Expression<int>? localRevision,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (path != null) 'path': path,
      if (rawMarkdown != null) 'rawMarkdown': rawMarkdown,
      if (body != null) 'body': body,
      if (aliases != null) 'aliases': aliases,
      if (summary != null) 'summary': summary,
      if (isDaily != null) 'isDaily': isDaily,
      if (isPinned != null) 'isPinned': isPinned,
      if (lastRemoteSha != null) 'lastRemoteSha': lastRemoteSha,
      if (isDirty != null) 'isDirty': isDirty,
      if (isPendingDeletion != null) 'isPendingDeletion': isPendingDeletion,
      if (pendingRenameFromPath != null)
        'pendingRenameFromPath': pendingRenameFromPath,
      if (pendingRenameFromSha != null)
        'pendingRenameFromSha': pendingRenameFromSha,
      if (isConflict != null) 'isConflict': isConflict,
      if (localRevision != null) 'localRevision': localRevision,
      if (updatedAt != null) 'updatedAt': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  NoteRowsCompanion copyWith({
    Value<String>? id,
    Value<String>? title,
    Value<String>? path,
    Value<String>? rawMarkdown,
    Value<String>? body,
    Value<String>? aliases,
    Value<String?>? summary,
    Value<bool>? isDaily,
    Value<bool>? isPinned,
    Value<String?>? lastRemoteSha,
    Value<bool>? isDirty,
    Value<bool>? isPendingDeletion,
    Value<String?>? pendingRenameFromPath,
    Value<String?>? pendingRenameFromSha,
    Value<bool>? isConflict,
    Value<int>? localRevision,
    Value<int>? updatedAt,
    Value<int>? rowid,
  }) {
    return NoteRowsCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      path: path ?? this.path,
      rawMarkdown: rawMarkdown ?? this.rawMarkdown,
      body: body ?? this.body,
      aliases: aliases ?? this.aliases,
      summary: summary ?? this.summary,
      isDaily: isDaily ?? this.isDaily,
      isPinned: isPinned ?? this.isPinned,
      lastRemoteSha: lastRemoteSha ?? this.lastRemoteSha,
      isDirty: isDirty ?? this.isDirty,
      isPendingDeletion: isPendingDeletion ?? this.isPendingDeletion,
      pendingRenameFromPath:
          pendingRenameFromPath ?? this.pendingRenameFromPath,
      pendingRenameFromSha: pendingRenameFromSha ?? this.pendingRenameFromSha,
      isConflict: isConflict ?? this.isConflict,
      localRevision: localRevision ?? this.localRevision,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (path.present) {
      map['path'] = Variable<String>(path.value);
    }
    if (rawMarkdown.present) {
      map['rawMarkdown'] = Variable<String>(rawMarkdown.value);
    }
    if (body.present) {
      map['body'] = Variable<String>(body.value);
    }
    if (aliases.present) {
      map['aliases'] = Variable<String>(aliases.value);
    }
    if (summary.present) {
      map['summary'] = Variable<String>(summary.value);
    }
    if (isDaily.present) {
      map['isDaily'] = Variable<bool>(isDaily.value);
    }
    if (isPinned.present) {
      map['isPinned'] = Variable<bool>(isPinned.value);
    }
    if (lastRemoteSha.present) {
      map['lastRemoteSha'] = Variable<String>(lastRemoteSha.value);
    }
    if (isDirty.present) {
      map['isDirty'] = Variable<bool>(isDirty.value);
    }
    if (isPendingDeletion.present) {
      map['isPendingDeletion'] = Variable<bool>(isPendingDeletion.value);
    }
    if (pendingRenameFromPath.present) {
      map['pendingRenameFromPath'] = Variable<String>(
        pendingRenameFromPath.value,
      );
    }
    if (pendingRenameFromSha.present) {
      map['pendingRenameFromSha'] = Variable<String>(
        pendingRenameFromSha.value,
      );
    }
    if (isConflict.present) {
      map['isConflict'] = Variable<bool>(isConflict.value);
    }
    if (localRevision.present) {
      map['localRevision'] = Variable<int>(localRevision.value);
    }
    if (updatedAt.present) {
      map['updatedAt'] = Variable<int>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('NoteRowsCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('path: $path, ')
          ..write('rawMarkdown: $rawMarkdown, ')
          ..write('body: $body, ')
          ..write('aliases: $aliases, ')
          ..write('summary: $summary, ')
          ..write('isDaily: $isDaily, ')
          ..write('isPinned: $isPinned, ')
          ..write('lastRemoteSha: $lastRemoteSha, ')
          ..write('isDirty: $isDirty, ')
          ..write('isPendingDeletion: $isPendingDeletion, ')
          ..write('pendingRenameFromPath: $pendingRenameFromPath, ')
          ..write('pendingRenameFromSha: $pendingRenameFromSha, ')
          ..write('isConflict: $isConflict, ')
          ..write('localRevision: $localRevision, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TodoEntriesTable extends TodoEntries
    with TableInfo<$TodoEntriesTable, TodoEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TodoEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _noteIdMeta = const VerificationMeta('noteId');
  @override
  late final GeneratedColumn<String> noteId = GeneratedColumn<String>(
    'noteId',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _taskIndexMeta = const VerificationMeta(
    'taskIndex',
  );
  @override
  late final GeneratedColumn<int> taskIndex = GeneratedColumn<int>(
    'taskIndex',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _taskTextMeta = const VerificationMeta(
    'taskText',
  );
  @override
  late final GeneratedColumn<String> taskText = GeneratedColumn<String>(
    'text',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isCompletedMeta = const VerificationMeta(
    'isCompleted',
  );
  @override
  late final GeneratedColumn<bool> isCompleted = GeneratedColumn<bool>(
    'isCompleted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("isCompleted" IN (0, 1))',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [
    noteId,
    taskIndex,
    taskText,
    isCompleted,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'todo_index';
  @override
  VerificationContext validateIntegrity(
    Insertable<TodoEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('noteId')) {
      context.handle(
        _noteIdMeta,
        noteId.isAcceptableOrUnknown(data['noteId']!, _noteIdMeta),
      );
    } else if (isInserting) {
      context.missing(_noteIdMeta);
    }
    if (data.containsKey('taskIndex')) {
      context.handle(
        _taskIndexMeta,
        taskIndex.isAcceptableOrUnknown(data['taskIndex']!, _taskIndexMeta),
      );
    } else if (isInserting) {
      context.missing(_taskIndexMeta);
    }
    if (data.containsKey('text')) {
      context.handle(
        _taskTextMeta,
        taskText.isAcceptableOrUnknown(data['text']!, _taskTextMeta),
      );
    } else if (isInserting) {
      context.missing(_taskTextMeta);
    }
    if (data.containsKey('isCompleted')) {
      context.handle(
        _isCompletedMeta,
        isCompleted.isAcceptableOrUnknown(
          data['isCompleted']!,
          _isCompletedMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_isCompletedMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {noteId, taskIndex};
  @override
  TodoEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TodoEntry(
      noteId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}noteId'],
      )!,
      taskIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}taskIndex'],
      )!,
      taskText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}text'],
      )!,
      isCompleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}isCompleted'],
      )!,
    );
  }

  @override
  $TodoEntriesTable createAlias(String alias) {
    return $TodoEntriesTable(attachedDatabase, alias);
  }
}

class TodoEntry extends DataClass implements Insertable<TodoEntry> {
  final String noteId;
  final int taskIndex;
  final String taskText;
  final bool isCompleted;
  const TodoEntry({
    required this.noteId,
    required this.taskIndex,
    required this.taskText,
    required this.isCompleted,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['noteId'] = Variable<String>(noteId);
    map['taskIndex'] = Variable<int>(taskIndex);
    map['text'] = Variable<String>(taskText);
    map['isCompleted'] = Variable<bool>(isCompleted);
    return map;
  }

  TodoEntriesCompanion toCompanion(bool nullToAbsent) {
    return TodoEntriesCompanion(
      noteId: Value(noteId),
      taskIndex: Value(taskIndex),
      taskText: Value(taskText),
      isCompleted: Value(isCompleted),
    );
  }

  factory TodoEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TodoEntry(
      noteId: serializer.fromJson<String>(json['noteId']),
      taskIndex: serializer.fromJson<int>(json['taskIndex']),
      taskText: serializer.fromJson<String>(json['taskText']),
      isCompleted: serializer.fromJson<bool>(json['isCompleted']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'noteId': serializer.toJson<String>(noteId),
      'taskIndex': serializer.toJson<int>(taskIndex),
      'taskText': serializer.toJson<String>(taskText),
      'isCompleted': serializer.toJson<bool>(isCompleted),
    };
  }

  TodoEntry copyWith({
    String? noteId,
    int? taskIndex,
    String? taskText,
    bool? isCompleted,
  }) => TodoEntry(
    noteId: noteId ?? this.noteId,
    taskIndex: taskIndex ?? this.taskIndex,
    taskText: taskText ?? this.taskText,
    isCompleted: isCompleted ?? this.isCompleted,
  );
  TodoEntry copyWithCompanion(TodoEntriesCompanion data) {
    return TodoEntry(
      noteId: data.noteId.present ? data.noteId.value : this.noteId,
      taskIndex: data.taskIndex.present ? data.taskIndex.value : this.taskIndex,
      taskText: data.taskText.present ? data.taskText.value : this.taskText,
      isCompleted: data.isCompleted.present
          ? data.isCompleted.value
          : this.isCompleted,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TodoEntry(')
          ..write('noteId: $noteId, ')
          ..write('taskIndex: $taskIndex, ')
          ..write('taskText: $taskText, ')
          ..write('isCompleted: $isCompleted')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(noteId, taskIndex, taskText, isCompleted);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TodoEntry &&
          other.noteId == this.noteId &&
          other.taskIndex == this.taskIndex &&
          other.taskText == this.taskText &&
          other.isCompleted == this.isCompleted);
}

class TodoEntriesCompanion extends UpdateCompanion<TodoEntry> {
  final Value<String> noteId;
  final Value<int> taskIndex;
  final Value<String> taskText;
  final Value<bool> isCompleted;
  final Value<int> rowid;
  const TodoEntriesCompanion({
    this.noteId = const Value.absent(),
    this.taskIndex = const Value.absent(),
    this.taskText = const Value.absent(),
    this.isCompleted = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TodoEntriesCompanion.insert({
    required String noteId,
    required int taskIndex,
    required String taskText,
    required bool isCompleted,
    this.rowid = const Value.absent(),
  }) : noteId = Value(noteId),
       taskIndex = Value(taskIndex),
       taskText = Value(taskText),
       isCompleted = Value(isCompleted);
  static Insertable<TodoEntry> custom({
    Expression<String>? noteId,
    Expression<int>? taskIndex,
    Expression<String>? taskText,
    Expression<bool>? isCompleted,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (noteId != null) 'noteId': noteId,
      if (taskIndex != null) 'taskIndex': taskIndex,
      if (taskText != null) 'text': taskText,
      if (isCompleted != null) 'isCompleted': isCompleted,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TodoEntriesCompanion copyWith({
    Value<String>? noteId,
    Value<int>? taskIndex,
    Value<String>? taskText,
    Value<bool>? isCompleted,
    Value<int>? rowid,
  }) {
    return TodoEntriesCompanion(
      noteId: noteId ?? this.noteId,
      taskIndex: taskIndex ?? this.taskIndex,
      taskText: taskText ?? this.taskText,
      isCompleted: isCompleted ?? this.isCompleted,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (noteId.present) {
      map['noteId'] = Variable<String>(noteId.value);
    }
    if (taskIndex.present) {
      map['taskIndex'] = Variable<int>(taskIndex.value);
    }
    if (taskText.present) {
      map['text'] = Variable<String>(taskText.value);
    }
    if (isCompleted.present) {
      map['isCompleted'] = Variable<bool>(isCompleted.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TodoEntriesCompanion(')
          ..write('noteId: $noteId, ')
          ..write('taskIndex: $taskIndex, ')
          ..write('taskText: $taskText, ')
          ..write('isCompleted: $isCompleted, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TodoIndexStatesTable extends TodoIndexStates
    with TableInfo<$TodoIndexStatesTable, TodoIndexState> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TodoIndexStatesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _isReadyMeta = const VerificationMeta(
    'isReady',
  );
  @override
  late final GeneratedColumn<bool> isReady = GeneratedColumn<bool>(
    'isReady',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("isReady" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [id, isReady];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'todo_index_state';
  @override
  VerificationContext validateIntegrity(
    Insertable<TodoIndexState> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('isReady')) {
      context.handle(
        _isReadyMeta,
        isReady.isAcceptableOrUnknown(data['isReady']!, _isReadyMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TodoIndexState map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TodoIndexState(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      isReady: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}isReady'],
      )!,
    );
  }

  @override
  $TodoIndexStatesTable createAlias(String alias) {
    return $TodoIndexStatesTable(attachedDatabase, alias);
  }
}

class TodoIndexState extends DataClass implements Insertable<TodoIndexState> {
  final int id;
  final bool isReady;
  const TodoIndexState({required this.id, required this.isReady});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['isReady'] = Variable<bool>(isReady);
    return map;
  }

  TodoIndexStatesCompanion toCompanion(bool nullToAbsent) {
    return TodoIndexStatesCompanion(id: Value(id), isReady: Value(isReady));
  }

  factory TodoIndexState.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TodoIndexState(
      id: serializer.fromJson<int>(json['id']),
      isReady: serializer.fromJson<bool>(json['isReady']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'isReady': serializer.toJson<bool>(isReady),
    };
  }

  TodoIndexState copyWith({int? id, bool? isReady}) =>
      TodoIndexState(id: id ?? this.id, isReady: isReady ?? this.isReady);
  TodoIndexState copyWithCompanion(TodoIndexStatesCompanion data) {
    return TodoIndexState(
      id: data.id.present ? data.id.value : this.id,
      isReady: data.isReady.present ? data.isReady.value : this.isReady,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TodoIndexState(')
          ..write('id: $id, ')
          ..write('isReady: $isReady')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, isReady);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TodoIndexState &&
          other.id == this.id &&
          other.isReady == this.isReady);
}

class TodoIndexStatesCompanion extends UpdateCompanion<TodoIndexState> {
  final Value<int> id;
  final Value<bool> isReady;
  const TodoIndexStatesCompanion({
    this.id = const Value.absent(),
    this.isReady = const Value.absent(),
  });
  TodoIndexStatesCompanion.insert({
    this.id = const Value.absent(),
    this.isReady = const Value.absent(),
  });
  static Insertable<TodoIndexState> custom({
    Expression<int>? id,
    Expression<bool>? isReady,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (isReady != null) 'isReady': isReady,
    });
  }

  TodoIndexStatesCompanion copyWith({Value<int>? id, Value<bool>? isReady}) {
    return TodoIndexStatesCompanion(
      id: id ?? this.id,
      isReady: isReady ?? this.isReady,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (isReady.present) {
      map['isReady'] = Variable<bool>(isReady.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TodoIndexStatesCompanion(')
          ..write('id: $id, ')
          ..write('isReady: $isReady')
          ..write(')'))
        .toString();
  }
}

class $AttachmentsTable extends Attachments
    with TableInfo<$AttachmentsTable, Attachment> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AttachmentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _pathMeta = const VerificationMeta('path');
  @override
  late final GeneratedColumn<String> path = GeneratedColumn<String>(
    'path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _mimeTypeMeta = const VerificationMeta(
    'mimeType',
  );
  @override
  late final GeneratedColumn<String> mimeType = GeneratedColumn<String>(
    'mimeType',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastRemoteShaMeta = const VerificationMeta(
    'lastRemoteSha',
  );
  @override
  late final GeneratedColumn<String> lastRemoteSha = GeneratedColumn<String>(
    'lastRemoteSha',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isDirtyMeta = const VerificationMeta(
    'isDirty',
  );
  @override
  late final GeneratedColumn<bool> isDirty = GeneratedColumn<bool>(
    'isDirty',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("isDirty" IN (0, 1))',
    ),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updatedAt',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    path,
    mimeType,
    lastRemoteSha,
    isDirty,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'attachments';
  @override
  VerificationContext validateIntegrity(
    Insertable<Attachment> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('path')) {
      context.handle(
        _pathMeta,
        path.isAcceptableOrUnknown(data['path']!, _pathMeta),
      );
    } else if (isInserting) {
      context.missing(_pathMeta);
    }
    if (data.containsKey('mimeType')) {
      context.handle(
        _mimeTypeMeta,
        mimeType.isAcceptableOrUnknown(data['mimeType']!, _mimeTypeMeta),
      );
    }
    if (data.containsKey('lastRemoteSha')) {
      context.handle(
        _lastRemoteShaMeta,
        lastRemoteSha.isAcceptableOrUnknown(
          data['lastRemoteSha']!,
          _lastRemoteShaMeta,
        ),
      );
    }
    if (data.containsKey('isDirty')) {
      context.handle(
        _isDirtyMeta,
        isDirty.isAcceptableOrUnknown(data['isDirty']!, _isDirtyMeta),
      );
    } else if (isInserting) {
      context.missing(_isDirtyMeta);
    }
    if (data.containsKey('updatedAt')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updatedAt']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {path};
  @override
  Attachment map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Attachment(
      path: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}path'],
      )!,
      mimeType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mimeType'],
      ),
      lastRemoteSha: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}lastRemoteSha'],
      ),
      isDirty: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}isDirty'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updatedAt'],
      )!,
    );
  }

  @override
  $AttachmentsTable createAlias(String alias) {
    return $AttachmentsTable(attachedDatabase, alias);
  }
}

class Attachment extends DataClass implements Insertable<Attachment> {
  final String path;
  final String? mimeType;
  final String? lastRemoteSha;
  final bool isDirty;
  final int updatedAt;
  const Attachment({
    required this.path,
    this.mimeType,
    this.lastRemoteSha,
    required this.isDirty,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['path'] = Variable<String>(path);
    if (!nullToAbsent || mimeType != null) {
      map['mimeType'] = Variable<String>(mimeType);
    }
    if (!nullToAbsent || lastRemoteSha != null) {
      map['lastRemoteSha'] = Variable<String>(lastRemoteSha);
    }
    map['isDirty'] = Variable<bool>(isDirty);
    map['updatedAt'] = Variable<int>(updatedAt);
    return map;
  }

  AttachmentsCompanion toCompanion(bool nullToAbsent) {
    return AttachmentsCompanion(
      path: Value(path),
      mimeType: mimeType == null && nullToAbsent
          ? const Value.absent()
          : Value(mimeType),
      lastRemoteSha: lastRemoteSha == null && nullToAbsent
          ? const Value.absent()
          : Value(lastRemoteSha),
      isDirty: Value(isDirty),
      updatedAt: Value(updatedAt),
    );
  }

  factory Attachment.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Attachment(
      path: serializer.fromJson<String>(json['path']),
      mimeType: serializer.fromJson<String?>(json['mimeType']),
      lastRemoteSha: serializer.fromJson<String?>(json['lastRemoteSha']),
      isDirty: serializer.fromJson<bool>(json['isDirty']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'path': serializer.toJson<String>(path),
      'mimeType': serializer.toJson<String?>(mimeType),
      'lastRemoteSha': serializer.toJson<String?>(lastRemoteSha),
      'isDirty': serializer.toJson<bool>(isDirty),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  Attachment copyWith({
    String? path,
    Value<String?> mimeType = const Value.absent(),
    Value<String?> lastRemoteSha = const Value.absent(),
    bool? isDirty,
    int? updatedAt,
  }) => Attachment(
    path: path ?? this.path,
    mimeType: mimeType.present ? mimeType.value : this.mimeType,
    lastRemoteSha: lastRemoteSha.present
        ? lastRemoteSha.value
        : this.lastRemoteSha,
    isDirty: isDirty ?? this.isDirty,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  Attachment copyWithCompanion(AttachmentsCompanion data) {
    return Attachment(
      path: data.path.present ? data.path.value : this.path,
      mimeType: data.mimeType.present ? data.mimeType.value : this.mimeType,
      lastRemoteSha: data.lastRemoteSha.present
          ? data.lastRemoteSha.value
          : this.lastRemoteSha,
      isDirty: data.isDirty.present ? data.isDirty.value : this.isDirty,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Attachment(')
          ..write('path: $path, ')
          ..write('mimeType: $mimeType, ')
          ..write('lastRemoteSha: $lastRemoteSha, ')
          ..write('isDirty: $isDirty, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(path, mimeType, lastRemoteSha, isDirty, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Attachment &&
          other.path == this.path &&
          other.mimeType == this.mimeType &&
          other.lastRemoteSha == this.lastRemoteSha &&
          other.isDirty == this.isDirty &&
          other.updatedAt == this.updatedAt);
}

class AttachmentsCompanion extends UpdateCompanion<Attachment> {
  final Value<String> path;
  final Value<String?> mimeType;
  final Value<String?> lastRemoteSha;
  final Value<bool> isDirty;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const AttachmentsCompanion({
    this.path = const Value.absent(),
    this.mimeType = const Value.absent(),
    this.lastRemoteSha = const Value.absent(),
    this.isDirty = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AttachmentsCompanion.insert({
    required String path,
    this.mimeType = const Value.absent(),
    this.lastRemoteSha = const Value.absent(),
    required bool isDirty,
    required int updatedAt,
    this.rowid = const Value.absent(),
  }) : path = Value(path),
       isDirty = Value(isDirty),
       updatedAt = Value(updatedAt);
  static Insertable<Attachment> custom({
    Expression<String>? path,
    Expression<String>? mimeType,
    Expression<String>? lastRemoteSha,
    Expression<bool>? isDirty,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (path != null) 'path': path,
      if (mimeType != null) 'mimeType': mimeType,
      if (lastRemoteSha != null) 'lastRemoteSha': lastRemoteSha,
      if (isDirty != null) 'isDirty': isDirty,
      if (updatedAt != null) 'updatedAt': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AttachmentsCompanion copyWith({
    Value<String>? path,
    Value<String?>? mimeType,
    Value<String?>? lastRemoteSha,
    Value<bool>? isDirty,
    Value<int>? updatedAt,
    Value<int>? rowid,
  }) {
    return AttachmentsCompanion(
      path: path ?? this.path,
      mimeType: mimeType ?? this.mimeType,
      lastRemoteSha: lastRemoteSha ?? this.lastRemoteSha,
      isDirty: isDirty ?? this.isDirty,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (path.present) {
      map['path'] = Variable<String>(path.value);
    }
    if (mimeType.present) {
      map['mimeType'] = Variable<String>(mimeType.value);
    }
    if (lastRemoteSha.present) {
      map['lastRemoteSha'] = Variable<String>(lastRemoteSha.value);
    }
    if (isDirty.present) {
      map['isDirty'] = Variable<bool>(isDirty.value);
    }
    if (updatedAt.present) {
      map['updatedAt'] = Variable<int>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AttachmentsCompanion(')
          ..write('path: $path, ')
          ..write('mimeType: $mimeType, ')
          ..write('lastRemoteSha: $lastRemoteSha, ')
          ..write('isDirty: $isDirty, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncOperationsTable extends SyncOperations
    with TableInfo<$SyncOperationsTable, SyncOperation> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncOperationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _noteIdMeta = const VerificationMeta('noteId');
  @override
  late final GeneratedColumn<String> noteId = GeneratedColumn<String>(
    'note_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pathMeta = const VerificationMeta('path');
  @override
  late final GeneratedColumn<String> path = GeneratedColumn<String>(
    'path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fromPathMeta = const VerificationMeta(
    'fromPath',
  );
  @override
  late final GeneratedColumn<String> fromPath = GeneratedColumn<String>(
    'from_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _localRevisionMeta = const VerificationMeta(
    'localRevision',
  );
  @override
  late final GeneratedColumn<int> localRevision = GeneratedColumn<int>(
    'local_revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    noteId,
    kind,
    path,
    fromPath,
    localRevision,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_operations';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncOperation> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('note_id')) {
      context.handle(
        _noteIdMeta,
        noteId.isAcceptableOrUnknown(data['note_id']!, _noteIdMeta),
      );
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('path')) {
      context.handle(
        _pathMeta,
        path.isAcceptableOrUnknown(data['path']!, _pathMeta),
      );
    } else if (isInserting) {
      context.missing(_pathMeta);
    }
    if (data.containsKey('from_path')) {
      context.handle(
        _fromPathMeta,
        fromPath.isAcceptableOrUnknown(data['from_path']!, _fromPathMeta),
      );
    }
    if (data.containsKey('local_revision')) {
      context.handle(
        _localRevisionMeta,
        localRevision.isAcceptableOrUnknown(
          data['local_revision']!,
          _localRevisionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_localRevisionMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SyncOperation map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncOperation(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      noteId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note_id'],
      ),
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      path: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}path'],
      )!,
      fromPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}from_path'],
      ),
      localRevision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}local_revision'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $SyncOperationsTable createAlias(String alias) {
    return $SyncOperationsTable(attachedDatabase, alias);
  }
}

class SyncOperation extends DataClass implements Insertable<SyncOperation> {
  final int id;
  final String? noteId;
  final String kind;
  final String path;
  final String? fromPath;
  final int localRevision;
  final int createdAt;
  const SyncOperation({
    required this.id,
    this.noteId,
    required this.kind,
    required this.path,
    this.fromPath,
    required this.localRevision,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    if (!nullToAbsent || noteId != null) {
      map['note_id'] = Variable<String>(noteId);
    }
    map['kind'] = Variable<String>(kind);
    map['path'] = Variable<String>(path);
    if (!nullToAbsent || fromPath != null) {
      map['from_path'] = Variable<String>(fromPath);
    }
    map['local_revision'] = Variable<int>(localRevision);
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  SyncOperationsCompanion toCompanion(bool nullToAbsent) {
    return SyncOperationsCompanion(
      id: Value(id),
      noteId: noteId == null && nullToAbsent
          ? const Value.absent()
          : Value(noteId),
      kind: Value(kind),
      path: Value(path),
      fromPath: fromPath == null && nullToAbsent
          ? const Value.absent()
          : Value(fromPath),
      localRevision: Value(localRevision),
      createdAt: Value(createdAt),
    );
  }

  factory SyncOperation.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncOperation(
      id: serializer.fromJson<int>(json['id']),
      noteId: serializer.fromJson<String?>(json['noteId']),
      kind: serializer.fromJson<String>(json['kind']),
      path: serializer.fromJson<String>(json['path']),
      fromPath: serializer.fromJson<String?>(json['fromPath']),
      localRevision: serializer.fromJson<int>(json['localRevision']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'noteId': serializer.toJson<String?>(noteId),
      'kind': serializer.toJson<String>(kind),
      'path': serializer.toJson<String>(path),
      'fromPath': serializer.toJson<String?>(fromPath),
      'localRevision': serializer.toJson<int>(localRevision),
      'createdAt': serializer.toJson<int>(createdAt),
    };
  }

  SyncOperation copyWith({
    int? id,
    Value<String?> noteId = const Value.absent(),
    String? kind,
    String? path,
    Value<String?> fromPath = const Value.absent(),
    int? localRevision,
    int? createdAt,
  }) => SyncOperation(
    id: id ?? this.id,
    noteId: noteId.present ? noteId.value : this.noteId,
    kind: kind ?? this.kind,
    path: path ?? this.path,
    fromPath: fromPath.present ? fromPath.value : this.fromPath,
    localRevision: localRevision ?? this.localRevision,
    createdAt: createdAt ?? this.createdAt,
  );
  SyncOperation copyWithCompanion(SyncOperationsCompanion data) {
    return SyncOperation(
      id: data.id.present ? data.id.value : this.id,
      noteId: data.noteId.present ? data.noteId.value : this.noteId,
      kind: data.kind.present ? data.kind.value : this.kind,
      path: data.path.present ? data.path.value : this.path,
      fromPath: data.fromPath.present ? data.fromPath.value : this.fromPath,
      localRevision: data.localRevision.present
          ? data.localRevision.value
          : this.localRevision,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncOperation(')
          ..write('id: $id, ')
          ..write('noteId: $noteId, ')
          ..write('kind: $kind, ')
          ..write('path: $path, ')
          ..write('fromPath: $fromPath, ')
          ..write('localRevision: $localRevision, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, noteId, kind, path, fromPath, localRevision, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncOperation &&
          other.id == this.id &&
          other.noteId == this.noteId &&
          other.kind == this.kind &&
          other.path == this.path &&
          other.fromPath == this.fromPath &&
          other.localRevision == this.localRevision &&
          other.createdAt == this.createdAt);
}

class SyncOperationsCompanion extends UpdateCompanion<SyncOperation> {
  final Value<int> id;
  final Value<String?> noteId;
  final Value<String> kind;
  final Value<String> path;
  final Value<String?> fromPath;
  final Value<int> localRevision;
  final Value<int> createdAt;
  const SyncOperationsCompanion({
    this.id = const Value.absent(),
    this.noteId = const Value.absent(),
    this.kind = const Value.absent(),
    this.path = const Value.absent(),
    this.fromPath = const Value.absent(),
    this.localRevision = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  SyncOperationsCompanion.insert({
    this.id = const Value.absent(),
    this.noteId = const Value.absent(),
    required String kind,
    required String path,
    this.fromPath = const Value.absent(),
    required int localRevision,
    required int createdAt,
  }) : kind = Value(kind),
       path = Value(path),
       localRevision = Value(localRevision),
       createdAt = Value(createdAt);
  static Insertable<SyncOperation> custom({
    Expression<int>? id,
    Expression<String>? noteId,
    Expression<String>? kind,
    Expression<String>? path,
    Expression<String>? fromPath,
    Expression<int>? localRevision,
    Expression<int>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (noteId != null) 'note_id': noteId,
      if (kind != null) 'kind': kind,
      if (path != null) 'path': path,
      if (fromPath != null) 'from_path': fromPath,
      if (localRevision != null) 'local_revision': localRevision,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  SyncOperationsCompanion copyWith({
    Value<int>? id,
    Value<String?>? noteId,
    Value<String>? kind,
    Value<String>? path,
    Value<String?>? fromPath,
    Value<int>? localRevision,
    Value<int>? createdAt,
  }) {
    return SyncOperationsCompanion(
      id: id ?? this.id,
      noteId: noteId ?? this.noteId,
      kind: kind ?? this.kind,
      path: path ?? this.path,
      fromPath: fromPath ?? this.fromPath,
      localRevision: localRevision ?? this.localRevision,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (noteId.present) {
      map['note_id'] = Variable<String>(noteId.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (path.present) {
      map['path'] = Variable<String>(path.value);
    }
    if (fromPath.present) {
      map['from_path'] = Variable<String>(fromPath.value);
    }
    if (localRevision.present) {
      map['local_revision'] = Variable<int>(localRevision.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncOperationsCompanion(')
          ..write('id: $id, ')
          ..write('noteId: $noteId, ')
          ..write('kind: $kind, ')
          ..write('path: $path, ')
          ..write('fromPath: $fromPath, ')
          ..write('localRevision: $localRevision, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $SyncLeasesTable extends SyncLeases
    with TableInfo<$SyncLeasesTable, SyncLease> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncLeasesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _scopeMeta = const VerificationMeta('scope');
  @override
  late final GeneratedColumn<String> scope = GeneratedColumn<String>(
    'scope',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ownerMeta = const VerificationMeta('owner');
  @override
  late final GeneratedColumn<String> owner = GeneratedColumn<String>(
    'owner',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _expiresAtMeta = const VerificationMeta(
    'expiresAt',
  );
  @override
  late final GeneratedColumn<int> expiresAt = GeneratedColumn<int>(
    'expiresAt',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [scope, owner, expiresAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_leases';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncLease> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('scope')) {
      context.handle(
        _scopeMeta,
        scope.isAcceptableOrUnknown(data['scope']!, _scopeMeta),
      );
    } else if (isInserting) {
      context.missing(_scopeMeta);
    }
    if (data.containsKey('owner')) {
      context.handle(
        _ownerMeta,
        owner.isAcceptableOrUnknown(data['owner']!, _ownerMeta),
      );
    } else if (isInserting) {
      context.missing(_ownerMeta);
    }
    if (data.containsKey('expiresAt')) {
      context.handle(
        _expiresAtMeta,
        expiresAt.isAcceptableOrUnknown(data['expiresAt']!, _expiresAtMeta),
      );
    } else if (isInserting) {
      context.missing(_expiresAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {scope};
  @override
  SyncLease map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncLease(
      scope: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}scope'],
      )!,
      owner: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner'],
      )!,
      expiresAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}expiresAt'],
      )!,
    );
  }

  @override
  $SyncLeasesTable createAlias(String alias) {
    return $SyncLeasesTable(attachedDatabase, alias);
  }
}

class SyncLease extends DataClass implements Insertable<SyncLease> {
  final String scope;
  final String owner;
  final int expiresAt;
  const SyncLease({
    required this.scope,
    required this.owner,
    required this.expiresAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['scope'] = Variable<String>(scope);
    map['owner'] = Variable<String>(owner);
    map['expiresAt'] = Variable<int>(expiresAt);
    return map;
  }

  SyncLeasesCompanion toCompanion(bool nullToAbsent) {
    return SyncLeasesCompanion(
      scope: Value(scope),
      owner: Value(owner),
      expiresAt: Value(expiresAt),
    );
  }

  factory SyncLease.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncLease(
      scope: serializer.fromJson<String>(json['scope']),
      owner: serializer.fromJson<String>(json['owner']),
      expiresAt: serializer.fromJson<int>(json['expiresAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'scope': serializer.toJson<String>(scope),
      'owner': serializer.toJson<String>(owner),
      'expiresAt': serializer.toJson<int>(expiresAt),
    };
  }

  SyncLease copyWith({String? scope, String? owner, int? expiresAt}) =>
      SyncLease(
        scope: scope ?? this.scope,
        owner: owner ?? this.owner,
        expiresAt: expiresAt ?? this.expiresAt,
      );
  SyncLease copyWithCompanion(SyncLeasesCompanion data) {
    return SyncLease(
      scope: data.scope.present ? data.scope.value : this.scope,
      owner: data.owner.present ? data.owner.value : this.owner,
      expiresAt: data.expiresAt.present ? data.expiresAt.value : this.expiresAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncLease(')
          ..write('scope: $scope, ')
          ..write('owner: $owner, ')
          ..write('expiresAt: $expiresAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(scope, owner, expiresAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncLease &&
          other.scope == this.scope &&
          other.owner == this.owner &&
          other.expiresAt == this.expiresAt);
}

class SyncLeasesCompanion extends UpdateCompanion<SyncLease> {
  final Value<String> scope;
  final Value<String> owner;
  final Value<int> expiresAt;
  final Value<int> rowid;
  const SyncLeasesCompanion({
    this.scope = const Value.absent(),
    this.owner = const Value.absent(),
    this.expiresAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncLeasesCompanion.insert({
    required String scope,
    required String owner,
    required int expiresAt,
    this.rowid = const Value.absent(),
  }) : scope = Value(scope),
       owner = Value(owner),
       expiresAt = Value(expiresAt);
  static Insertable<SyncLease> custom({
    Expression<String>? scope,
    Expression<String>? owner,
    Expression<int>? expiresAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (scope != null) 'scope': scope,
      if (owner != null) 'owner': owner,
      if (expiresAt != null) 'expiresAt': expiresAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncLeasesCompanion copyWith({
    Value<String>? scope,
    Value<String>? owner,
    Value<int>? expiresAt,
    Value<int>? rowid,
  }) {
    return SyncLeasesCompanion(
      scope: scope ?? this.scope,
      owner: owner ?? this.owner,
      expiresAt: expiresAt ?? this.expiresAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (scope.present) {
      map['scope'] = Variable<String>(scope.value);
    }
    if (owner.present) {
      map['owner'] = Variable<String>(owner.value);
    }
    if (expiresAt.present) {
      map['expiresAt'] = Variable<int>(expiresAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncLeasesCompanion(')
          ..write('scope: $scope, ')
          ..write('owner: $owner, ')
          ..write('expiresAt: $expiresAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $NoteRowsTable noteRows = $NoteRowsTable(this);
  late final $TodoEntriesTable todoEntries = $TodoEntriesTable(this);
  late final $TodoIndexStatesTable todoIndexStates = $TodoIndexStatesTable(
    this,
  );
  late final $AttachmentsTable attachments = $AttachmentsTable(this);
  late final $SyncOperationsTable syncOperations = $SyncOperationsTable(this);
  late final $SyncLeasesTable syncLeases = $SyncLeasesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    noteRows,
    todoEntries,
    todoIndexStates,
    attachments,
    syncOperations,
    syncLeases,
  ];
}

typedef $$NoteRowsTableCreateCompanionBuilder =
    NoteRowsCompanion Function({
      required String id,
      required String title,
      required String path,
      required String rawMarkdown,
      required String body,
      required String aliases,
      Value<String?> summary,
      required bool isDaily,
      Value<bool> isPinned,
      Value<String?> lastRemoteSha,
      Value<bool> isDirty,
      Value<bool> isPendingDeletion,
      Value<String?> pendingRenameFromPath,
      Value<String?> pendingRenameFromSha,
      Value<bool> isConflict,
      Value<int> localRevision,
      required int updatedAt,
      Value<int> rowid,
    });
typedef $$NoteRowsTableUpdateCompanionBuilder =
    NoteRowsCompanion Function({
      Value<String> id,
      Value<String> title,
      Value<String> path,
      Value<String> rawMarkdown,
      Value<String> body,
      Value<String> aliases,
      Value<String?> summary,
      Value<bool> isDaily,
      Value<bool> isPinned,
      Value<String?> lastRemoteSha,
      Value<bool> isDirty,
      Value<bool> isPendingDeletion,
      Value<String?> pendingRenameFromPath,
      Value<String?> pendingRenameFromSha,
      Value<bool> isConflict,
      Value<int> localRevision,
      Value<int> updatedAt,
      Value<int> rowid,
    });

class $$NoteRowsTableFilterComposer
    extends Composer<_$AppDatabase, $NoteRowsTable> {
  $$NoteRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rawMarkdown => $composableBuilder(
    column: $table.rawMarkdown,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get aliases => $composableBuilder(
    column: $table.aliases,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get summary => $composableBuilder(
    column: $table.summary,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isDaily => $composableBuilder(
    column: $table.isDaily,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isPinned => $composableBuilder(
    column: $table.isPinned,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastRemoteSha => $composableBuilder(
    column: $table.lastRemoteSha,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isDirty => $composableBuilder(
    column: $table.isDirty,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isPendingDeletion => $composableBuilder(
    column: $table.isPendingDeletion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get pendingRenameFromPath => $composableBuilder(
    column: $table.pendingRenameFromPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get pendingRenameFromSha => $composableBuilder(
    column: $table.pendingRenameFromSha,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isConflict => $composableBuilder(
    column: $table.isConflict,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get localRevision => $composableBuilder(
    column: $table.localRevision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$NoteRowsTableOrderingComposer
    extends Composer<_$AppDatabase, $NoteRowsTable> {
  $$NoteRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rawMarkdown => $composableBuilder(
    column: $table.rawMarkdown,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get aliases => $composableBuilder(
    column: $table.aliases,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get summary => $composableBuilder(
    column: $table.summary,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isDaily => $composableBuilder(
    column: $table.isDaily,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isPinned => $composableBuilder(
    column: $table.isPinned,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastRemoteSha => $composableBuilder(
    column: $table.lastRemoteSha,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isDirty => $composableBuilder(
    column: $table.isDirty,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isPendingDeletion => $composableBuilder(
    column: $table.isPendingDeletion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get pendingRenameFromPath => $composableBuilder(
    column: $table.pendingRenameFromPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get pendingRenameFromSha => $composableBuilder(
    column: $table.pendingRenameFromSha,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isConflict => $composableBuilder(
    column: $table.isConflict,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get localRevision => $composableBuilder(
    column: $table.localRevision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$NoteRowsTableAnnotationComposer
    extends Composer<_$AppDatabase, $NoteRowsTable> {
  $$NoteRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get path =>
      $composableBuilder(column: $table.path, builder: (column) => column);

  GeneratedColumn<String> get rawMarkdown => $composableBuilder(
    column: $table.rawMarkdown,
    builder: (column) => column,
  );

  GeneratedColumn<String> get body =>
      $composableBuilder(column: $table.body, builder: (column) => column);

  GeneratedColumn<String> get aliases =>
      $composableBuilder(column: $table.aliases, builder: (column) => column);

  GeneratedColumn<String> get summary =>
      $composableBuilder(column: $table.summary, builder: (column) => column);

  GeneratedColumn<bool> get isDaily =>
      $composableBuilder(column: $table.isDaily, builder: (column) => column);

  GeneratedColumn<bool> get isPinned =>
      $composableBuilder(column: $table.isPinned, builder: (column) => column);

  GeneratedColumn<String> get lastRemoteSha => $composableBuilder(
    column: $table.lastRemoteSha,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isDirty =>
      $composableBuilder(column: $table.isDirty, builder: (column) => column);

  GeneratedColumn<bool> get isPendingDeletion => $composableBuilder(
    column: $table.isPendingDeletion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get pendingRenameFromPath => $composableBuilder(
    column: $table.pendingRenameFromPath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get pendingRenameFromSha => $composableBuilder(
    column: $table.pendingRenameFromSha,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isConflict => $composableBuilder(
    column: $table.isConflict,
    builder: (column) => column,
  );

  GeneratedColumn<int> get localRevision => $composableBuilder(
    column: $table.localRevision,
    builder: (column) => column,
  );

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$NoteRowsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $NoteRowsTable,
          NoteRow,
          $$NoteRowsTableFilterComposer,
          $$NoteRowsTableOrderingComposer,
          $$NoteRowsTableAnnotationComposer,
          $$NoteRowsTableCreateCompanionBuilder,
          $$NoteRowsTableUpdateCompanionBuilder,
          (NoteRow, BaseReferences<_$AppDatabase, $NoteRowsTable, NoteRow>),
          NoteRow,
          PrefetchHooks Function()
        > {
  $$NoteRowsTableTableManager(_$AppDatabase db, $NoteRowsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$NoteRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$NoteRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$NoteRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> path = const Value.absent(),
                Value<String> rawMarkdown = const Value.absent(),
                Value<String> body = const Value.absent(),
                Value<String> aliases = const Value.absent(),
                Value<String?> summary = const Value.absent(),
                Value<bool> isDaily = const Value.absent(),
                Value<bool> isPinned = const Value.absent(),
                Value<String?> lastRemoteSha = const Value.absent(),
                Value<bool> isDirty = const Value.absent(),
                Value<bool> isPendingDeletion = const Value.absent(),
                Value<String?> pendingRenameFromPath = const Value.absent(),
                Value<String?> pendingRenameFromSha = const Value.absent(),
                Value<bool> isConflict = const Value.absent(),
                Value<int> localRevision = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => NoteRowsCompanion(
                id: id,
                title: title,
                path: path,
                rawMarkdown: rawMarkdown,
                body: body,
                aliases: aliases,
                summary: summary,
                isDaily: isDaily,
                isPinned: isPinned,
                lastRemoteSha: lastRemoteSha,
                isDirty: isDirty,
                isPendingDeletion: isPendingDeletion,
                pendingRenameFromPath: pendingRenameFromPath,
                pendingRenameFromSha: pendingRenameFromSha,
                isConflict: isConflict,
                localRevision: localRevision,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String title,
                required String path,
                required String rawMarkdown,
                required String body,
                required String aliases,
                Value<String?> summary = const Value.absent(),
                required bool isDaily,
                Value<bool> isPinned = const Value.absent(),
                Value<String?> lastRemoteSha = const Value.absent(),
                Value<bool> isDirty = const Value.absent(),
                Value<bool> isPendingDeletion = const Value.absent(),
                Value<String?> pendingRenameFromPath = const Value.absent(),
                Value<String?> pendingRenameFromSha = const Value.absent(),
                Value<bool> isConflict = const Value.absent(),
                Value<int> localRevision = const Value.absent(),
                required int updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => NoteRowsCompanion.insert(
                id: id,
                title: title,
                path: path,
                rawMarkdown: rawMarkdown,
                body: body,
                aliases: aliases,
                summary: summary,
                isDaily: isDaily,
                isPinned: isPinned,
                lastRemoteSha: lastRemoteSha,
                isDirty: isDirty,
                isPendingDeletion: isPendingDeletion,
                pendingRenameFromPath: pendingRenameFromPath,
                pendingRenameFromSha: pendingRenameFromSha,
                isConflict: isConflict,
                localRevision: localRevision,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$NoteRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $NoteRowsTable,
      NoteRow,
      $$NoteRowsTableFilterComposer,
      $$NoteRowsTableOrderingComposer,
      $$NoteRowsTableAnnotationComposer,
      $$NoteRowsTableCreateCompanionBuilder,
      $$NoteRowsTableUpdateCompanionBuilder,
      (NoteRow, BaseReferences<_$AppDatabase, $NoteRowsTable, NoteRow>),
      NoteRow,
      PrefetchHooks Function()
    >;
typedef $$TodoEntriesTableCreateCompanionBuilder =
    TodoEntriesCompanion Function({
      required String noteId,
      required int taskIndex,
      required String taskText,
      required bool isCompleted,
      Value<int> rowid,
    });
typedef $$TodoEntriesTableUpdateCompanionBuilder =
    TodoEntriesCompanion Function({
      Value<String> noteId,
      Value<int> taskIndex,
      Value<String> taskText,
      Value<bool> isCompleted,
      Value<int> rowid,
    });

class $$TodoEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $TodoEntriesTable> {
  $$TodoEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get noteId => $composableBuilder(
    column: $table.noteId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get taskIndex => $composableBuilder(
    column: $table.taskIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get taskText => $composableBuilder(
    column: $table.taskText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isCompleted => $composableBuilder(
    column: $table.isCompleted,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TodoEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $TodoEntriesTable> {
  $$TodoEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get noteId => $composableBuilder(
    column: $table.noteId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get taskIndex => $composableBuilder(
    column: $table.taskIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get taskText => $composableBuilder(
    column: $table.taskText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isCompleted => $composableBuilder(
    column: $table.isCompleted,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TodoEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $TodoEntriesTable> {
  $$TodoEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get noteId =>
      $composableBuilder(column: $table.noteId, builder: (column) => column);

  GeneratedColumn<int> get taskIndex =>
      $composableBuilder(column: $table.taskIndex, builder: (column) => column);

  GeneratedColumn<String> get taskText =>
      $composableBuilder(column: $table.taskText, builder: (column) => column);

  GeneratedColumn<bool> get isCompleted => $composableBuilder(
    column: $table.isCompleted,
    builder: (column) => column,
  );
}

class $$TodoEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TodoEntriesTable,
          TodoEntry,
          $$TodoEntriesTableFilterComposer,
          $$TodoEntriesTableOrderingComposer,
          $$TodoEntriesTableAnnotationComposer,
          $$TodoEntriesTableCreateCompanionBuilder,
          $$TodoEntriesTableUpdateCompanionBuilder,
          (
            TodoEntry,
            BaseReferences<_$AppDatabase, $TodoEntriesTable, TodoEntry>,
          ),
          TodoEntry,
          PrefetchHooks Function()
        > {
  $$TodoEntriesTableTableManager(_$AppDatabase db, $TodoEntriesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TodoEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TodoEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TodoEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> noteId = const Value.absent(),
                Value<int> taskIndex = const Value.absent(),
                Value<String> taskText = const Value.absent(),
                Value<bool> isCompleted = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TodoEntriesCompanion(
                noteId: noteId,
                taskIndex: taskIndex,
                taskText: taskText,
                isCompleted: isCompleted,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String noteId,
                required int taskIndex,
                required String taskText,
                required bool isCompleted,
                Value<int> rowid = const Value.absent(),
              }) => TodoEntriesCompanion.insert(
                noteId: noteId,
                taskIndex: taskIndex,
                taskText: taskText,
                isCompleted: isCompleted,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TodoEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TodoEntriesTable,
      TodoEntry,
      $$TodoEntriesTableFilterComposer,
      $$TodoEntriesTableOrderingComposer,
      $$TodoEntriesTableAnnotationComposer,
      $$TodoEntriesTableCreateCompanionBuilder,
      $$TodoEntriesTableUpdateCompanionBuilder,
      (TodoEntry, BaseReferences<_$AppDatabase, $TodoEntriesTable, TodoEntry>),
      TodoEntry,
      PrefetchHooks Function()
    >;
typedef $$TodoIndexStatesTableCreateCompanionBuilder =
    TodoIndexStatesCompanion Function({Value<int> id, Value<bool> isReady});
typedef $$TodoIndexStatesTableUpdateCompanionBuilder =
    TodoIndexStatesCompanion Function({Value<int> id, Value<bool> isReady});

class $$TodoIndexStatesTableFilterComposer
    extends Composer<_$AppDatabase, $TodoIndexStatesTable> {
  $$TodoIndexStatesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isReady => $composableBuilder(
    column: $table.isReady,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TodoIndexStatesTableOrderingComposer
    extends Composer<_$AppDatabase, $TodoIndexStatesTable> {
  $$TodoIndexStatesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isReady => $composableBuilder(
    column: $table.isReady,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TodoIndexStatesTableAnnotationComposer
    extends Composer<_$AppDatabase, $TodoIndexStatesTable> {
  $$TodoIndexStatesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<bool> get isReady =>
      $composableBuilder(column: $table.isReady, builder: (column) => column);
}

class $$TodoIndexStatesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TodoIndexStatesTable,
          TodoIndexState,
          $$TodoIndexStatesTableFilterComposer,
          $$TodoIndexStatesTableOrderingComposer,
          $$TodoIndexStatesTableAnnotationComposer,
          $$TodoIndexStatesTableCreateCompanionBuilder,
          $$TodoIndexStatesTableUpdateCompanionBuilder,
          (
            TodoIndexState,
            BaseReferences<
              _$AppDatabase,
              $TodoIndexStatesTable,
              TodoIndexState
            >,
          ),
          TodoIndexState,
          PrefetchHooks Function()
        > {
  $$TodoIndexStatesTableTableManager(
    _$AppDatabase db,
    $TodoIndexStatesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TodoIndexStatesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TodoIndexStatesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TodoIndexStatesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<bool> isReady = const Value.absent(),
              }) => TodoIndexStatesCompanion(id: id, isReady: isReady),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<bool> isReady = const Value.absent(),
              }) => TodoIndexStatesCompanion.insert(id: id, isReady: isReady),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TodoIndexStatesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TodoIndexStatesTable,
      TodoIndexState,
      $$TodoIndexStatesTableFilterComposer,
      $$TodoIndexStatesTableOrderingComposer,
      $$TodoIndexStatesTableAnnotationComposer,
      $$TodoIndexStatesTableCreateCompanionBuilder,
      $$TodoIndexStatesTableUpdateCompanionBuilder,
      (
        TodoIndexState,
        BaseReferences<_$AppDatabase, $TodoIndexStatesTable, TodoIndexState>,
      ),
      TodoIndexState,
      PrefetchHooks Function()
    >;
typedef $$AttachmentsTableCreateCompanionBuilder =
    AttachmentsCompanion Function({
      required String path,
      Value<String?> mimeType,
      Value<String?> lastRemoteSha,
      required bool isDirty,
      required int updatedAt,
      Value<int> rowid,
    });
typedef $$AttachmentsTableUpdateCompanionBuilder =
    AttachmentsCompanion Function({
      Value<String> path,
      Value<String?> mimeType,
      Value<String?> lastRemoteSha,
      Value<bool> isDirty,
      Value<int> updatedAt,
      Value<int> rowid,
    });

class $$AttachmentsTableFilterComposer
    extends Composer<_$AppDatabase, $AttachmentsTable> {
  $$AttachmentsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mimeType => $composableBuilder(
    column: $table.mimeType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastRemoteSha => $composableBuilder(
    column: $table.lastRemoteSha,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isDirty => $composableBuilder(
    column: $table.isDirty,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AttachmentsTableOrderingComposer
    extends Composer<_$AppDatabase, $AttachmentsTable> {
  $$AttachmentsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mimeType => $composableBuilder(
    column: $table.mimeType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastRemoteSha => $composableBuilder(
    column: $table.lastRemoteSha,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isDirty => $composableBuilder(
    column: $table.isDirty,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AttachmentsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AttachmentsTable> {
  $$AttachmentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get path =>
      $composableBuilder(column: $table.path, builder: (column) => column);

  GeneratedColumn<String> get mimeType =>
      $composableBuilder(column: $table.mimeType, builder: (column) => column);

  GeneratedColumn<String> get lastRemoteSha => $composableBuilder(
    column: $table.lastRemoteSha,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isDirty =>
      $composableBuilder(column: $table.isDirty, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$AttachmentsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AttachmentsTable,
          Attachment,
          $$AttachmentsTableFilterComposer,
          $$AttachmentsTableOrderingComposer,
          $$AttachmentsTableAnnotationComposer,
          $$AttachmentsTableCreateCompanionBuilder,
          $$AttachmentsTableUpdateCompanionBuilder,
          (
            Attachment,
            BaseReferences<_$AppDatabase, $AttachmentsTable, Attachment>,
          ),
          Attachment,
          PrefetchHooks Function()
        > {
  $$AttachmentsTableTableManager(_$AppDatabase db, $AttachmentsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AttachmentsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AttachmentsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AttachmentsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> path = const Value.absent(),
                Value<String?> mimeType = const Value.absent(),
                Value<String?> lastRemoteSha = const Value.absent(),
                Value<bool> isDirty = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AttachmentsCompanion(
                path: path,
                mimeType: mimeType,
                lastRemoteSha: lastRemoteSha,
                isDirty: isDirty,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String path,
                Value<String?> mimeType = const Value.absent(),
                Value<String?> lastRemoteSha = const Value.absent(),
                required bool isDirty,
                required int updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => AttachmentsCompanion.insert(
                path: path,
                mimeType: mimeType,
                lastRemoteSha: lastRemoteSha,
                isDirty: isDirty,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AttachmentsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AttachmentsTable,
      Attachment,
      $$AttachmentsTableFilterComposer,
      $$AttachmentsTableOrderingComposer,
      $$AttachmentsTableAnnotationComposer,
      $$AttachmentsTableCreateCompanionBuilder,
      $$AttachmentsTableUpdateCompanionBuilder,
      (
        Attachment,
        BaseReferences<_$AppDatabase, $AttachmentsTable, Attachment>,
      ),
      Attachment,
      PrefetchHooks Function()
    >;
typedef $$SyncOperationsTableCreateCompanionBuilder =
    SyncOperationsCompanion Function({
      Value<int> id,
      Value<String?> noteId,
      required String kind,
      required String path,
      Value<String?> fromPath,
      required int localRevision,
      required int createdAt,
    });
typedef $$SyncOperationsTableUpdateCompanionBuilder =
    SyncOperationsCompanion Function({
      Value<int> id,
      Value<String?> noteId,
      Value<String> kind,
      Value<String> path,
      Value<String?> fromPath,
      Value<int> localRevision,
      Value<int> createdAt,
    });

class $$SyncOperationsTableFilterComposer
    extends Composer<_$AppDatabase, $SyncOperationsTable> {
  $$SyncOperationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get noteId => $composableBuilder(
    column: $table.noteId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fromPath => $composableBuilder(
    column: $table.fromPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get localRevision => $composableBuilder(
    column: $table.localRevision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncOperationsTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncOperationsTable> {
  $$SyncOperationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get noteId => $composableBuilder(
    column: $table.noteId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fromPath => $composableBuilder(
    column: $table.fromPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get localRevision => $composableBuilder(
    column: $table.localRevision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncOperationsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncOperationsTable> {
  $$SyncOperationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get noteId =>
      $composableBuilder(column: $table.noteId, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get path =>
      $composableBuilder(column: $table.path, builder: (column) => column);

  GeneratedColumn<String> get fromPath =>
      $composableBuilder(column: $table.fromPath, builder: (column) => column);

  GeneratedColumn<int> get localRevision => $composableBuilder(
    column: $table.localRevision,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$SyncOperationsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SyncOperationsTable,
          SyncOperation,
          $$SyncOperationsTableFilterComposer,
          $$SyncOperationsTableOrderingComposer,
          $$SyncOperationsTableAnnotationComposer,
          $$SyncOperationsTableCreateCompanionBuilder,
          $$SyncOperationsTableUpdateCompanionBuilder,
          (
            SyncOperation,
            BaseReferences<_$AppDatabase, $SyncOperationsTable, SyncOperation>,
          ),
          SyncOperation,
          PrefetchHooks Function()
        > {
  $$SyncOperationsTableTableManager(
    _$AppDatabase db,
    $SyncOperationsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncOperationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncOperationsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncOperationsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String?> noteId = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> path = const Value.absent(),
                Value<String?> fromPath = const Value.absent(),
                Value<int> localRevision = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
              }) => SyncOperationsCompanion(
                id: id,
                noteId: noteId,
                kind: kind,
                path: path,
                fromPath: fromPath,
                localRevision: localRevision,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String?> noteId = const Value.absent(),
                required String kind,
                required String path,
                Value<String?> fromPath = const Value.absent(),
                required int localRevision,
                required int createdAt,
              }) => SyncOperationsCompanion.insert(
                id: id,
                noteId: noteId,
                kind: kind,
                path: path,
                fromPath: fromPath,
                localRevision: localRevision,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncOperationsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SyncOperationsTable,
      SyncOperation,
      $$SyncOperationsTableFilterComposer,
      $$SyncOperationsTableOrderingComposer,
      $$SyncOperationsTableAnnotationComposer,
      $$SyncOperationsTableCreateCompanionBuilder,
      $$SyncOperationsTableUpdateCompanionBuilder,
      (
        SyncOperation,
        BaseReferences<_$AppDatabase, $SyncOperationsTable, SyncOperation>,
      ),
      SyncOperation,
      PrefetchHooks Function()
    >;
typedef $$SyncLeasesTableCreateCompanionBuilder =
    SyncLeasesCompanion Function({
      required String scope,
      required String owner,
      required int expiresAt,
      Value<int> rowid,
    });
typedef $$SyncLeasesTableUpdateCompanionBuilder =
    SyncLeasesCompanion Function({
      Value<String> scope,
      Value<String> owner,
      Value<int> expiresAt,
      Value<int> rowid,
    });

class $$SyncLeasesTableFilterComposer
    extends Composer<_$AppDatabase, $SyncLeasesTable> {
  $$SyncLeasesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get scope => $composableBuilder(
    column: $table.scope,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get owner => $composableBuilder(
    column: $table.owner,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get expiresAt => $composableBuilder(
    column: $table.expiresAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncLeasesTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncLeasesTable> {
  $$SyncLeasesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get scope => $composableBuilder(
    column: $table.scope,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get owner => $composableBuilder(
    column: $table.owner,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get expiresAt => $composableBuilder(
    column: $table.expiresAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncLeasesTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncLeasesTable> {
  $$SyncLeasesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get scope =>
      $composableBuilder(column: $table.scope, builder: (column) => column);

  GeneratedColumn<String> get owner =>
      $composableBuilder(column: $table.owner, builder: (column) => column);

  GeneratedColumn<int> get expiresAt =>
      $composableBuilder(column: $table.expiresAt, builder: (column) => column);
}

class $$SyncLeasesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SyncLeasesTable,
          SyncLease,
          $$SyncLeasesTableFilterComposer,
          $$SyncLeasesTableOrderingComposer,
          $$SyncLeasesTableAnnotationComposer,
          $$SyncLeasesTableCreateCompanionBuilder,
          $$SyncLeasesTableUpdateCompanionBuilder,
          (
            SyncLease,
            BaseReferences<_$AppDatabase, $SyncLeasesTable, SyncLease>,
          ),
          SyncLease,
          PrefetchHooks Function()
        > {
  $$SyncLeasesTableTableManager(_$AppDatabase db, $SyncLeasesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncLeasesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncLeasesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncLeasesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> scope = const Value.absent(),
                Value<String> owner = const Value.absent(),
                Value<int> expiresAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncLeasesCompanion(
                scope: scope,
                owner: owner,
                expiresAt: expiresAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String scope,
                required String owner,
                required int expiresAt,
                Value<int> rowid = const Value.absent(),
              }) => SyncLeasesCompanion.insert(
                scope: scope,
                owner: owner,
                expiresAt: expiresAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncLeasesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SyncLeasesTable,
      SyncLease,
      $$SyncLeasesTableFilterComposer,
      $$SyncLeasesTableOrderingComposer,
      $$SyncLeasesTableAnnotationComposer,
      $$SyncLeasesTableCreateCompanionBuilder,
      $$SyncLeasesTableUpdateCompanionBuilder,
      (SyncLease, BaseReferences<_$AppDatabase, $SyncLeasesTable, SyncLease>),
      SyncLease,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$NoteRowsTableTableManager get noteRows =>
      $$NoteRowsTableTableManager(_db, _db.noteRows);
  $$TodoEntriesTableTableManager get todoEntries =>
      $$TodoEntriesTableTableManager(_db, _db.todoEntries);
  $$TodoIndexStatesTableTableManager get todoIndexStates =>
      $$TodoIndexStatesTableTableManager(_db, _db.todoIndexStates);
  $$AttachmentsTableTableManager get attachments =>
      $$AttachmentsTableTableManager(_db, _db.attachments);
  $$SyncOperationsTableTableManager get syncOperations =>
      $$SyncOperationsTableTableManager(_db, _db.syncOperations);
  $$SyncLeasesTableTableManager get syncLeases =>
      $$SyncLeasesTableTableManager(_db, _db.syncLeases);
}
