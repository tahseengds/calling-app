// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'local_db.dart';

// ignore_for_file: type=lint
mixin _$MessagesDaoMixin on DatabaseAccessor<AppDatabase> {
  $MessagesTableTable get messagesTable => attachedDatabase.messagesTable;
}
mixin _$ConversationsDaoMixin on DatabaseAccessor<AppDatabase> {
  $ConversationsTableTable get conversationsTable =>
      attachedDatabase.conversationsTable;
}
mixin _$UsersDaoMixin on DatabaseAccessor<AppDatabase> {
  $UsersTableTable get usersTable => attachedDatabase.usersTable;
}
mixin _$CallRecordsDaoMixin on DatabaseAccessor<AppDatabase> {
  $CallRecordsTableTable get callRecordsTable =>
      attachedDatabase.callRecordsTable;
}
mixin _$PendingMediaUploadsDaoMixin on DatabaseAccessor<AppDatabase> {
  $PendingMediaUploadsTableTable get pendingMediaUploadsTable =>
      attachedDatabase.pendingMediaUploadsTable;
}

class $MessagesTableTable extends MessagesTable
    with TableInfo<$MessagesTableTable, MessageRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MessagesTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _conversationIdMeta =
      const VerificationMeta('conversationId');
  @override
  late final GeneratedColumn<String> conversationId = GeneratedColumn<String>(
      'conversation_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _senderIdMeta =
      const VerificationMeta('senderId');
  @override
  late final GeneratedColumn<String> senderId = GeneratedColumn<String>(
      'sender_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _messageTypeMeta =
      const VerificationMeta('messageType');
  @override
  late final GeneratedColumn<String> messageType = GeneratedColumn<String>(
      'message_type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _contentMeta =
      const VerificationMeta('content');
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
      'content', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _mediaLocalPathMeta =
      const VerificationMeta('mediaLocalPath');
  @override
  late final GeneratedColumn<String> mediaLocalPath = GeneratedColumn<String>(
      'media_local_path', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _mediaRemoteUrlMeta =
      const VerificationMeta('mediaRemoteUrl');
  @override
  late final GeneratedColumn<String> mediaRemoteUrl = GeneratedColumn<String>(
      'media_remote_url', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _thumbnailUrlMeta =
      const VerificationMeta('thumbnailUrl');
  @override
  late final GeneratedColumn<String> thumbnailUrl = GeneratedColumn<String>(
      'thumbnail_url', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
      'status', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('sent'));
  static const VerificationMeta _replyToIdMeta =
      const VerificationMeta('replyToId');
  @override
  late final GeneratedColumn<String> replyToId = GeneratedColumn<String>(
      'reply_to_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _isSyncedMeta =
      const VerificationMeta('isSynced');
  @override
  late final GeneratedColumn<bool> isSynced = GeneratedColumn<bool>(
      'is_synced', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_synced" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _isDeletedMeta =
      const VerificationMeta('isDeleted');
  @override
  late final GeneratedColumn<bool> isDeleted = GeneratedColumn<bool>(
      'is_deleted', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_deleted" IN (0, 1))'),
      defaultValue: const Constant(false));
  @override
  List<GeneratedColumn> get $columns => [
        id,
        conversationId,
        senderId,
        messageType,
        content,
        mediaLocalPath,
        mediaRemoteUrl,
        thumbnailUrl,
        status,
        replyToId,
        createdAt,
        isSynced,
        isDeleted
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'messages_table';
  @override
  VerificationContext validateIntegrity(Insertable<MessageRow> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('conversation_id')) {
      context.handle(
          _conversationIdMeta,
          conversationId.isAcceptableOrUnknown(
              data['conversation_id']!, _conversationIdMeta));
    } else if (isInserting) {
      context.missing(_conversationIdMeta);
    }
    if (data.containsKey('sender_id')) {
      context.handle(_senderIdMeta,
          senderId.isAcceptableOrUnknown(data['sender_id']!, _senderIdMeta));
    } else if (isInserting) {
      context.missing(_senderIdMeta);
    }
    if (data.containsKey('message_type')) {
      context.handle(
          _messageTypeMeta,
          messageType.isAcceptableOrUnknown(
              data['message_type']!, _messageTypeMeta));
    } else if (isInserting) {
      context.missing(_messageTypeMeta);
    }
    if (data.containsKey('content')) {
      context.handle(_contentMeta,
          content.isAcceptableOrUnknown(data['content']!, _contentMeta));
    }
    if (data.containsKey('media_local_path')) {
      context.handle(
          _mediaLocalPathMeta,
          mediaLocalPath.isAcceptableOrUnknown(
              data['media_local_path']!, _mediaLocalPathMeta));
    }
    if (data.containsKey('media_remote_url')) {
      context.handle(
          _mediaRemoteUrlMeta,
          mediaRemoteUrl.isAcceptableOrUnknown(
              data['media_remote_url']!, _mediaRemoteUrlMeta));
    }
    if (data.containsKey('thumbnail_url')) {
      context.handle(
          _thumbnailUrlMeta,
          thumbnailUrl.isAcceptableOrUnknown(
              data['thumbnail_url']!, _thumbnailUrlMeta));
    }
    if (data.containsKey('status')) {
      context.handle(_statusMeta,
          status.isAcceptableOrUnknown(data['status']!, _statusMeta));
    }
    if (data.containsKey('reply_to_id')) {
      context.handle(
          _replyToIdMeta,
          replyToId.isAcceptableOrUnknown(
              data['reply_to_id']!, _replyToIdMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('is_synced')) {
      context.handle(_isSyncedMeta,
          isSynced.isAcceptableOrUnknown(data['is_synced']!, _isSyncedMeta));
    }
    if (data.containsKey('is_deleted')) {
      context.handle(_isDeletedMeta,
          isDeleted.isAcceptableOrUnknown(data['is_deleted']!, _isDeletedMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  MessageRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MessageRow(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      conversationId: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}conversation_id'])!,
      senderId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}sender_id'])!,
      messageType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}message_type'])!,
      content: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}content']),
      mediaLocalPath: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}media_local_path']),
      mediaRemoteUrl: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}media_remote_url']),
      thumbnailUrl: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}thumbnail_url']),
      status: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}status'])!,
      replyToId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}reply_to_id']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      isSynced: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_synced'])!,
      isDeleted: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_deleted'])!,
    );
  }

  @override
  $MessagesTableTable createAlias(String alias) {
    return $MessagesTableTable(attachedDatabase, alias);
  }
}

class MessageRow extends DataClass implements Insertable<MessageRow> {
  final String id;
  final String conversationId;
  final String senderId;
  final String messageType;
  final String? content;
  final String? mediaLocalPath;
  final String? mediaRemoteUrl;
  final String? thumbnailUrl;
  final String status;
  final String? replyToId;
  final DateTime createdAt;
  final bool isSynced;
  final bool isDeleted;
  const MessageRow(
      {required this.id,
      required this.conversationId,
      required this.senderId,
      required this.messageType,
      this.content,
      this.mediaLocalPath,
      this.mediaRemoteUrl,
      this.thumbnailUrl,
      required this.status,
      this.replyToId,
      required this.createdAt,
      required this.isSynced,
      required this.isDeleted});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['conversation_id'] = Variable<String>(conversationId);
    map['sender_id'] = Variable<String>(senderId);
    map['message_type'] = Variable<String>(messageType);
    if (!nullToAbsent || content != null) {
      map['content'] = Variable<String>(content);
    }
    if (!nullToAbsent || mediaLocalPath != null) {
      map['media_local_path'] = Variable<String>(mediaLocalPath);
    }
    if (!nullToAbsent || mediaRemoteUrl != null) {
      map['media_remote_url'] = Variable<String>(mediaRemoteUrl);
    }
    if (!nullToAbsent || thumbnailUrl != null) {
      map['thumbnail_url'] = Variable<String>(thumbnailUrl);
    }
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || replyToId != null) {
      map['reply_to_id'] = Variable<String>(replyToId);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['is_synced'] = Variable<bool>(isSynced);
    map['is_deleted'] = Variable<bool>(isDeleted);
    return map;
  }

  MessagesTableCompanion toCompanion(bool nullToAbsent) {
    return MessagesTableCompanion(
      id: Value(id),
      conversationId: Value(conversationId),
      senderId: Value(senderId),
      messageType: Value(messageType),
      content: content == null && nullToAbsent
          ? const Value.absent()
          : Value(content),
      mediaLocalPath: mediaLocalPath == null && nullToAbsent
          ? const Value.absent()
          : Value(mediaLocalPath),
      mediaRemoteUrl: mediaRemoteUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(mediaRemoteUrl),
      thumbnailUrl: thumbnailUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(thumbnailUrl),
      status: Value(status),
      replyToId: replyToId == null && nullToAbsent
          ? const Value.absent()
          : Value(replyToId),
      createdAt: Value(createdAt),
      isSynced: Value(isSynced),
      isDeleted: Value(isDeleted),
    );
  }

  factory MessageRow.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MessageRow(
      id: serializer.fromJson<String>(json['id']),
      conversationId: serializer.fromJson<String>(json['conversationId']),
      senderId: serializer.fromJson<String>(json['senderId']),
      messageType: serializer.fromJson<String>(json['messageType']),
      content: serializer.fromJson<String?>(json['content']),
      mediaLocalPath: serializer.fromJson<String?>(json['mediaLocalPath']),
      mediaRemoteUrl: serializer.fromJson<String?>(json['mediaRemoteUrl']),
      thumbnailUrl: serializer.fromJson<String?>(json['thumbnailUrl']),
      status: serializer.fromJson<String>(json['status']),
      replyToId: serializer.fromJson<String?>(json['replyToId']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      isSynced: serializer.fromJson<bool>(json['isSynced']),
      isDeleted: serializer.fromJson<bool>(json['isDeleted']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'conversationId': serializer.toJson<String>(conversationId),
      'senderId': serializer.toJson<String>(senderId),
      'messageType': serializer.toJson<String>(messageType),
      'content': serializer.toJson<String?>(content),
      'mediaLocalPath': serializer.toJson<String?>(mediaLocalPath),
      'mediaRemoteUrl': serializer.toJson<String?>(mediaRemoteUrl),
      'thumbnailUrl': serializer.toJson<String?>(thumbnailUrl),
      'status': serializer.toJson<String>(status),
      'replyToId': serializer.toJson<String?>(replyToId),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'isSynced': serializer.toJson<bool>(isSynced),
      'isDeleted': serializer.toJson<bool>(isDeleted),
    };
  }

  MessageRow copyWith(
          {String? id,
          String? conversationId,
          String? senderId,
          String? messageType,
          Value<String?> content = const Value.absent(),
          Value<String?> mediaLocalPath = const Value.absent(),
          Value<String?> mediaRemoteUrl = const Value.absent(),
          Value<String?> thumbnailUrl = const Value.absent(),
          String? status,
          Value<String?> replyToId = const Value.absent(),
          DateTime? createdAt,
          bool? isSynced,
          bool? isDeleted}) =>
      MessageRow(
        id: id ?? this.id,
        conversationId: conversationId ?? this.conversationId,
        senderId: senderId ?? this.senderId,
        messageType: messageType ?? this.messageType,
        content: content.present ? content.value : this.content,
        mediaLocalPath:
            mediaLocalPath.present ? mediaLocalPath.value : this.mediaLocalPath,
        mediaRemoteUrl:
            mediaRemoteUrl.present ? mediaRemoteUrl.value : this.mediaRemoteUrl,
        thumbnailUrl:
            thumbnailUrl.present ? thumbnailUrl.value : this.thumbnailUrl,
        status: status ?? this.status,
        replyToId: replyToId.present ? replyToId.value : this.replyToId,
        createdAt: createdAt ?? this.createdAt,
        isSynced: isSynced ?? this.isSynced,
        isDeleted: isDeleted ?? this.isDeleted,
      );
  MessageRow copyWithCompanion(MessagesTableCompanion data) {
    return MessageRow(
      id: data.id.present ? data.id.value : this.id,
      conversationId: data.conversationId.present
          ? data.conversationId.value
          : this.conversationId,
      senderId: data.senderId.present ? data.senderId.value : this.senderId,
      messageType:
          data.messageType.present ? data.messageType.value : this.messageType,
      content: data.content.present ? data.content.value : this.content,
      mediaLocalPath: data.mediaLocalPath.present
          ? data.mediaLocalPath.value
          : this.mediaLocalPath,
      mediaRemoteUrl: data.mediaRemoteUrl.present
          ? data.mediaRemoteUrl.value
          : this.mediaRemoteUrl,
      thumbnailUrl: data.thumbnailUrl.present
          ? data.thumbnailUrl.value
          : this.thumbnailUrl,
      status: data.status.present ? data.status.value : this.status,
      replyToId: data.replyToId.present ? data.replyToId.value : this.replyToId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      isSynced: data.isSynced.present ? data.isSynced.value : this.isSynced,
      isDeleted: data.isDeleted.present ? data.isDeleted.value : this.isDeleted,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MessageRow(')
          ..write('id: $id, ')
          ..write('conversationId: $conversationId, ')
          ..write('senderId: $senderId, ')
          ..write('messageType: $messageType, ')
          ..write('content: $content, ')
          ..write('mediaLocalPath: $mediaLocalPath, ')
          ..write('mediaRemoteUrl: $mediaRemoteUrl, ')
          ..write('thumbnailUrl: $thumbnailUrl, ')
          ..write('status: $status, ')
          ..write('replyToId: $replyToId, ')
          ..write('createdAt: $createdAt, ')
          ..write('isSynced: $isSynced, ')
          ..write('isDeleted: $isDeleted')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      conversationId,
      senderId,
      messageType,
      content,
      mediaLocalPath,
      mediaRemoteUrl,
      thumbnailUrl,
      status,
      replyToId,
      createdAt,
      isSynced,
      isDeleted);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MessageRow &&
          other.id == this.id &&
          other.conversationId == this.conversationId &&
          other.senderId == this.senderId &&
          other.messageType == this.messageType &&
          other.content == this.content &&
          other.mediaLocalPath == this.mediaLocalPath &&
          other.mediaRemoteUrl == this.mediaRemoteUrl &&
          other.thumbnailUrl == this.thumbnailUrl &&
          other.status == this.status &&
          other.replyToId == this.replyToId &&
          other.createdAt == this.createdAt &&
          other.isSynced == this.isSynced &&
          other.isDeleted == this.isDeleted);
}

class MessagesTableCompanion extends UpdateCompanion<MessageRow> {
  final Value<String> id;
  final Value<String> conversationId;
  final Value<String> senderId;
  final Value<String> messageType;
  final Value<String?> content;
  final Value<String?> mediaLocalPath;
  final Value<String?> mediaRemoteUrl;
  final Value<String?> thumbnailUrl;
  final Value<String> status;
  final Value<String?> replyToId;
  final Value<DateTime> createdAt;
  final Value<bool> isSynced;
  final Value<bool> isDeleted;
  final Value<int> rowid;
  const MessagesTableCompanion({
    this.id = const Value.absent(),
    this.conversationId = const Value.absent(),
    this.senderId = const Value.absent(),
    this.messageType = const Value.absent(),
    this.content = const Value.absent(),
    this.mediaLocalPath = const Value.absent(),
    this.mediaRemoteUrl = const Value.absent(),
    this.thumbnailUrl = const Value.absent(),
    this.status = const Value.absent(),
    this.replyToId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.isSynced = const Value.absent(),
    this.isDeleted = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MessagesTableCompanion.insert({
    required String id,
    required String conversationId,
    required String senderId,
    required String messageType,
    this.content = const Value.absent(),
    this.mediaLocalPath = const Value.absent(),
    this.mediaRemoteUrl = const Value.absent(),
    this.thumbnailUrl = const Value.absent(),
    this.status = const Value.absent(),
    this.replyToId = const Value.absent(),
    required DateTime createdAt,
    this.isSynced = const Value.absent(),
    this.isDeleted = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        conversationId = Value(conversationId),
        senderId = Value(senderId),
        messageType = Value(messageType),
        createdAt = Value(createdAt);
  static Insertable<MessageRow> custom({
    Expression<String>? id,
    Expression<String>? conversationId,
    Expression<String>? senderId,
    Expression<String>? messageType,
    Expression<String>? content,
    Expression<String>? mediaLocalPath,
    Expression<String>? mediaRemoteUrl,
    Expression<String>? thumbnailUrl,
    Expression<String>? status,
    Expression<String>? replyToId,
    Expression<DateTime>? createdAt,
    Expression<bool>? isSynced,
    Expression<bool>? isDeleted,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (conversationId != null) 'conversation_id': conversationId,
      if (senderId != null) 'sender_id': senderId,
      if (messageType != null) 'message_type': messageType,
      if (content != null) 'content': content,
      if (mediaLocalPath != null) 'media_local_path': mediaLocalPath,
      if (mediaRemoteUrl != null) 'media_remote_url': mediaRemoteUrl,
      if (thumbnailUrl != null) 'thumbnail_url': thumbnailUrl,
      if (status != null) 'status': status,
      if (replyToId != null) 'reply_to_id': replyToId,
      if (createdAt != null) 'created_at': createdAt,
      if (isSynced != null) 'is_synced': isSynced,
      if (isDeleted != null) 'is_deleted': isDeleted,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MessagesTableCompanion copyWith(
      {Value<String>? id,
      Value<String>? conversationId,
      Value<String>? senderId,
      Value<String>? messageType,
      Value<String?>? content,
      Value<String?>? mediaLocalPath,
      Value<String?>? mediaRemoteUrl,
      Value<String?>? thumbnailUrl,
      Value<String>? status,
      Value<String?>? replyToId,
      Value<DateTime>? createdAt,
      Value<bool>? isSynced,
      Value<bool>? isDeleted,
      Value<int>? rowid}) {
    return MessagesTableCompanion(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      senderId: senderId ?? this.senderId,
      messageType: messageType ?? this.messageType,
      content: content ?? this.content,
      mediaLocalPath: mediaLocalPath ?? this.mediaLocalPath,
      mediaRemoteUrl: mediaRemoteUrl ?? this.mediaRemoteUrl,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      status: status ?? this.status,
      replyToId: replyToId ?? this.replyToId,
      createdAt: createdAt ?? this.createdAt,
      isSynced: isSynced ?? this.isSynced,
      isDeleted: isDeleted ?? this.isDeleted,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (conversationId.present) {
      map['conversation_id'] = Variable<String>(conversationId.value);
    }
    if (senderId.present) {
      map['sender_id'] = Variable<String>(senderId.value);
    }
    if (messageType.present) {
      map['message_type'] = Variable<String>(messageType.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (mediaLocalPath.present) {
      map['media_local_path'] = Variable<String>(mediaLocalPath.value);
    }
    if (mediaRemoteUrl.present) {
      map['media_remote_url'] = Variable<String>(mediaRemoteUrl.value);
    }
    if (thumbnailUrl.present) {
      map['thumbnail_url'] = Variable<String>(thumbnailUrl.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (replyToId.present) {
      map['reply_to_id'] = Variable<String>(replyToId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (isSynced.present) {
      map['is_synced'] = Variable<bool>(isSynced.value);
    }
    if (isDeleted.present) {
      map['is_deleted'] = Variable<bool>(isDeleted.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MessagesTableCompanion(')
          ..write('id: $id, ')
          ..write('conversationId: $conversationId, ')
          ..write('senderId: $senderId, ')
          ..write('messageType: $messageType, ')
          ..write('content: $content, ')
          ..write('mediaLocalPath: $mediaLocalPath, ')
          ..write('mediaRemoteUrl: $mediaRemoteUrl, ')
          ..write('thumbnailUrl: $thumbnailUrl, ')
          ..write('status: $status, ')
          ..write('replyToId: $replyToId, ')
          ..write('createdAt: $createdAt, ')
          ..write('isSynced: $isSynced, ')
          ..write('isDeleted: $isDeleted, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ConversationsTableTable extends ConversationsTable
    with TableInfo<$ConversationsTableTable, ConversationRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ConversationsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _otherUserIdMeta =
      const VerificationMeta('otherUserId');
  @override
  late final GeneratedColumn<String> otherUserId = GeneratedColumn<String>(
      'other_user_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _lastMessageIdMeta =
      const VerificationMeta('lastMessageId');
  @override
  late final GeneratedColumn<String> lastMessageId = GeneratedColumn<String>(
      'last_message_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _lastActivityMeta =
      const VerificationMeta('lastActivity');
  @override
  late final GeneratedColumn<DateTime> lastActivity = GeneratedColumn<DateTime>(
      'last_activity', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _unreadCountMeta =
      const VerificationMeta('unreadCount');
  @override
  late final GeneratedColumn<int> unreadCount = GeneratedColumn<int>(
      'unread_count', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  @override
  List<GeneratedColumn> get $columns =>
      [id, otherUserId, lastMessageId, lastActivity, unreadCount];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'conversations_table';
  @override
  VerificationContext validateIntegrity(Insertable<ConversationRow> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('other_user_id')) {
      context.handle(
          _otherUserIdMeta,
          otherUserId.isAcceptableOrUnknown(
              data['other_user_id']!, _otherUserIdMeta));
    } else if (isInserting) {
      context.missing(_otherUserIdMeta);
    }
    if (data.containsKey('last_message_id')) {
      context.handle(
          _lastMessageIdMeta,
          lastMessageId.isAcceptableOrUnknown(
              data['last_message_id']!, _lastMessageIdMeta));
    }
    if (data.containsKey('last_activity')) {
      context.handle(
          _lastActivityMeta,
          lastActivity.isAcceptableOrUnknown(
              data['last_activity']!, _lastActivityMeta));
    } else if (isInserting) {
      context.missing(_lastActivityMeta);
    }
    if (data.containsKey('unread_count')) {
      context.handle(
          _unreadCountMeta,
          unreadCount.isAcceptableOrUnknown(
              data['unread_count']!, _unreadCountMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ConversationRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ConversationRow(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      otherUserId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}other_user_id'])!,
      lastMessageId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}last_message_id']),
      lastActivity: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime, data['${effectivePrefix}last_activity'])!,
      unreadCount: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}unread_count'])!,
    );
  }

  @override
  $ConversationsTableTable createAlias(String alias) {
    return $ConversationsTableTable(attachedDatabase, alias);
  }
}

class ConversationRow extends DataClass implements Insertable<ConversationRow> {
  final String id;
  final String otherUserId;
  final String? lastMessageId;
  final DateTime lastActivity;
  final int unreadCount;
  const ConversationRow(
      {required this.id,
      required this.otherUserId,
      this.lastMessageId,
      required this.lastActivity,
      required this.unreadCount});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['other_user_id'] = Variable<String>(otherUserId);
    if (!nullToAbsent || lastMessageId != null) {
      map['last_message_id'] = Variable<String>(lastMessageId);
    }
    map['last_activity'] = Variable<DateTime>(lastActivity);
    map['unread_count'] = Variable<int>(unreadCount);
    return map;
  }

  ConversationsTableCompanion toCompanion(bool nullToAbsent) {
    return ConversationsTableCompanion(
      id: Value(id),
      otherUserId: Value(otherUserId),
      lastMessageId: lastMessageId == null && nullToAbsent
          ? const Value.absent()
          : Value(lastMessageId),
      lastActivity: Value(lastActivity),
      unreadCount: Value(unreadCount),
    );
  }

  factory ConversationRow.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ConversationRow(
      id: serializer.fromJson<String>(json['id']),
      otherUserId: serializer.fromJson<String>(json['otherUserId']),
      lastMessageId: serializer.fromJson<String?>(json['lastMessageId']),
      lastActivity: serializer.fromJson<DateTime>(json['lastActivity']),
      unreadCount: serializer.fromJson<int>(json['unreadCount']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'otherUserId': serializer.toJson<String>(otherUserId),
      'lastMessageId': serializer.toJson<String?>(lastMessageId),
      'lastActivity': serializer.toJson<DateTime>(lastActivity),
      'unreadCount': serializer.toJson<int>(unreadCount),
    };
  }

  ConversationRow copyWith(
          {String? id,
          String? otherUserId,
          Value<String?> lastMessageId = const Value.absent(),
          DateTime? lastActivity,
          int? unreadCount}) =>
      ConversationRow(
        id: id ?? this.id,
        otherUserId: otherUserId ?? this.otherUserId,
        lastMessageId:
            lastMessageId.present ? lastMessageId.value : this.lastMessageId,
        lastActivity: lastActivity ?? this.lastActivity,
        unreadCount: unreadCount ?? this.unreadCount,
      );
  ConversationRow copyWithCompanion(ConversationsTableCompanion data) {
    return ConversationRow(
      id: data.id.present ? data.id.value : this.id,
      otherUserId:
          data.otherUserId.present ? data.otherUserId.value : this.otherUserId,
      lastMessageId: data.lastMessageId.present
          ? data.lastMessageId.value
          : this.lastMessageId,
      lastActivity: data.lastActivity.present
          ? data.lastActivity.value
          : this.lastActivity,
      unreadCount:
          data.unreadCount.present ? data.unreadCount.value : this.unreadCount,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ConversationRow(')
          ..write('id: $id, ')
          ..write('otherUserId: $otherUserId, ')
          ..write('lastMessageId: $lastMessageId, ')
          ..write('lastActivity: $lastActivity, ')
          ..write('unreadCount: $unreadCount')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, otherUserId, lastMessageId, lastActivity, unreadCount);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ConversationRow &&
          other.id == this.id &&
          other.otherUserId == this.otherUserId &&
          other.lastMessageId == this.lastMessageId &&
          other.lastActivity == this.lastActivity &&
          other.unreadCount == this.unreadCount);
}

class ConversationsTableCompanion extends UpdateCompanion<ConversationRow> {
  final Value<String> id;
  final Value<String> otherUserId;
  final Value<String?> lastMessageId;
  final Value<DateTime> lastActivity;
  final Value<int> unreadCount;
  final Value<int> rowid;
  const ConversationsTableCompanion({
    this.id = const Value.absent(),
    this.otherUserId = const Value.absent(),
    this.lastMessageId = const Value.absent(),
    this.lastActivity = const Value.absent(),
    this.unreadCount = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ConversationsTableCompanion.insert({
    required String id,
    required String otherUserId,
    this.lastMessageId = const Value.absent(),
    required DateTime lastActivity,
    this.unreadCount = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        otherUserId = Value(otherUserId),
        lastActivity = Value(lastActivity);
  static Insertable<ConversationRow> custom({
    Expression<String>? id,
    Expression<String>? otherUserId,
    Expression<String>? lastMessageId,
    Expression<DateTime>? lastActivity,
    Expression<int>? unreadCount,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (otherUserId != null) 'other_user_id': otherUserId,
      if (lastMessageId != null) 'last_message_id': lastMessageId,
      if (lastActivity != null) 'last_activity': lastActivity,
      if (unreadCount != null) 'unread_count': unreadCount,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ConversationsTableCompanion copyWith(
      {Value<String>? id,
      Value<String>? otherUserId,
      Value<String?>? lastMessageId,
      Value<DateTime>? lastActivity,
      Value<int>? unreadCount,
      Value<int>? rowid}) {
    return ConversationsTableCompanion(
      id: id ?? this.id,
      otherUserId: otherUserId ?? this.otherUserId,
      lastMessageId: lastMessageId ?? this.lastMessageId,
      lastActivity: lastActivity ?? this.lastActivity,
      unreadCount: unreadCount ?? this.unreadCount,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (otherUserId.present) {
      map['other_user_id'] = Variable<String>(otherUserId.value);
    }
    if (lastMessageId.present) {
      map['last_message_id'] = Variable<String>(lastMessageId.value);
    }
    if (lastActivity.present) {
      map['last_activity'] = Variable<DateTime>(lastActivity.value);
    }
    if (unreadCount.present) {
      map['unread_count'] = Variable<int>(unreadCount.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ConversationsTableCompanion(')
          ..write('id: $id, ')
          ..write('otherUserId: $otherUserId, ')
          ..write('lastMessageId: $lastMessageId, ')
          ..write('lastActivity: $lastActivity, ')
          ..write('unreadCount: $unreadCount, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $UsersTableTable extends UsersTable
    with TableInfo<$UsersTableTable, UserRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $UsersTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _phoneMeta = const VerificationMeta('phone');
  @override
  late final GeneratedColumn<String> phone = GeneratedColumn<String>(
      'phone', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _avatarUrlMeta =
      const VerificationMeta('avatarUrl');
  @override
  late final GeneratedColumn<String> avatarUrl = GeneratedColumn<String>(
      'avatar_url', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _lastSeenMeta =
      const VerificationMeta('lastSeen');
  @override
  late final GeneratedColumn<DateTime> lastSeen = GeneratedColumn<DateTime>(
      'last_seen', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _presenceMeta =
      const VerificationMeta('presence');
  @override
  late final GeneratedColumn<String> presence = GeneratedColumn<String>(
      'presence', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('offline'));
  @override
  List<GeneratedColumn> get $columns =>
      [id, name, phone, avatarUrl, lastSeen, presence];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'users_table';
  @override
  VerificationContext validateIntegrity(Insertable<UserRow> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('phone')) {
      context.handle(
          _phoneMeta, phone.isAcceptableOrUnknown(data['phone']!, _phoneMeta));
    } else if (isInserting) {
      context.missing(_phoneMeta);
    }
    if (data.containsKey('avatar_url')) {
      context.handle(_avatarUrlMeta,
          avatarUrl.isAcceptableOrUnknown(data['avatar_url']!, _avatarUrlMeta));
    }
    if (data.containsKey('last_seen')) {
      context.handle(_lastSeenMeta,
          lastSeen.isAcceptableOrUnknown(data['last_seen']!, _lastSeenMeta));
    } else if (isInserting) {
      context.missing(_lastSeenMeta);
    }
    if (data.containsKey('presence')) {
      context.handle(_presenceMeta,
          presence.isAcceptableOrUnknown(data['presence']!, _presenceMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  UserRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return UserRow(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      phone: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}phone'])!,
      avatarUrl: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}avatar_url']),
      lastSeen: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}last_seen'])!,
      presence: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}presence'])!,
    );
  }

  @override
  $UsersTableTable createAlias(String alias) {
    return $UsersTableTable(attachedDatabase, alias);
  }
}

class UserRow extends DataClass implements Insertable<UserRow> {
  final String id;
  final String name;
  final String phone;
  final String? avatarUrl;
  final DateTime lastSeen;
  final String presence;
  const UserRow(
      {required this.id,
      required this.name,
      required this.phone,
      this.avatarUrl,
      required this.lastSeen,
      required this.presence});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['phone'] = Variable<String>(phone);
    if (!nullToAbsent || avatarUrl != null) {
      map['avatar_url'] = Variable<String>(avatarUrl);
    }
    map['last_seen'] = Variable<DateTime>(lastSeen);
    map['presence'] = Variable<String>(presence);
    return map;
  }

  UsersTableCompanion toCompanion(bool nullToAbsent) {
    return UsersTableCompanion(
      id: Value(id),
      name: Value(name),
      phone: Value(phone),
      avatarUrl: avatarUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(avatarUrl),
      lastSeen: Value(lastSeen),
      presence: Value(presence),
    );
  }

  factory UserRow.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return UserRow(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      phone: serializer.fromJson<String>(json['phone']),
      avatarUrl: serializer.fromJson<String?>(json['avatarUrl']),
      lastSeen: serializer.fromJson<DateTime>(json['lastSeen']),
      presence: serializer.fromJson<String>(json['presence']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'phone': serializer.toJson<String>(phone),
      'avatarUrl': serializer.toJson<String?>(avatarUrl),
      'lastSeen': serializer.toJson<DateTime>(lastSeen),
      'presence': serializer.toJson<String>(presence),
    };
  }

  UserRow copyWith(
          {String? id,
          String? name,
          String? phone,
          Value<String?> avatarUrl = const Value.absent(),
          DateTime? lastSeen,
          String? presence}) =>
      UserRow(
        id: id ?? this.id,
        name: name ?? this.name,
        phone: phone ?? this.phone,
        avatarUrl: avatarUrl.present ? avatarUrl.value : this.avatarUrl,
        lastSeen: lastSeen ?? this.lastSeen,
        presence: presence ?? this.presence,
      );
  UserRow copyWithCompanion(UsersTableCompanion data) {
    return UserRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      phone: data.phone.present ? data.phone.value : this.phone,
      avatarUrl: data.avatarUrl.present ? data.avatarUrl.value : this.avatarUrl,
      lastSeen: data.lastSeen.present ? data.lastSeen.value : this.lastSeen,
      presence: data.presence.present ? data.presence.value : this.presence,
    );
  }

  @override
  String toString() {
    return (StringBuffer('UserRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('phone: $phone, ')
          ..write('avatarUrl: $avatarUrl, ')
          ..write('lastSeen: $lastSeen, ')
          ..write('presence: $presence')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, name, phone, avatarUrl, lastSeen, presence);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is UserRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.phone == this.phone &&
          other.avatarUrl == this.avatarUrl &&
          other.lastSeen == this.lastSeen &&
          other.presence == this.presence);
}

class UsersTableCompanion extends UpdateCompanion<UserRow> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> phone;
  final Value<String?> avatarUrl;
  final Value<DateTime> lastSeen;
  final Value<String> presence;
  final Value<int> rowid;
  const UsersTableCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.phone = const Value.absent(),
    this.avatarUrl = const Value.absent(),
    this.lastSeen = const Value.absent(),
    this.presence = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  UsersTableCompanion.insert({
    required String id,
    required String name,
    required String phone,
    this.avatarUrl = const Value.absent(),
    required DateTime lastSeen,
    this.presence = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        name = Value(name),
        phone = Value(phone),
        lastSeen = Value(lastSeen);
  static Insertable<UserRow> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? phone,
    Expression<String>? avatarUrl,
    Expression<DateTime>? lastSeen,
    Expression<String>? presence,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (phone != null) 'phone': phone,
      if (avatarUrl != null) 'avatar_url': avatarUrl,
      if (lastSeen != null) 'last_seen': lastSeen,
      if (presence != null) 'presence': presence,
      if (rowid != null) 'rowid': rowid,
    });
  }

  UsersTableCompanion copyWith(
      {Value<String>? id,
      Value<String>? name,
      Value<String>? phone,
      Value<String?>? avatarUrl,
      Value<DateTime>? lastSeen,
      Value<String>? presence,
      Value<int>? rowid}) {
    return UsersTableCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      lastSeen: lastSeen ?? this.lastSeen,
      presence: presence ?? this.presence,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (phone.present) {
      map['phone'] = Variable<String>(phone.value);
    }
    if (avatarUrl.present) {
      map['avatar_url'] = Variable<String>(avatarUrl.value);
    }
    if (lastSeen.present) {
      map['last_seen'] = Variable<DateTime>(lastSeen.value);
    }
    if (presence.present) {
      map['presence'] = Variable<String>(presence.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('UsersTableCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('phone: $phone, ')
          ..write('avatarUrl: $avatarUrl, ')
          ..write('lastSeen: $lastSeen, ')
          ..write('presence: $presence, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CallRecordsTableTable extends CallRecordsTable
    with TableInfo<$CallRecordsTableTable, CallRecordRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CallRecordsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _otherUserIdMeta =
      const VerificationMeta('otherUserId');
  @override
  late final GeneratedColumn<String> otherUserId = GeneratedColumn<String>(
      'other_user_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _callTypeMeta =
      const VerificationMeta('callType');
  @override
  late final GeneratedColumn<String> callType = GeneratedColumn<String>(
      'call_type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
      'status', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _startedAtMeta =
      const VerificationMeta('startedAt');
  @override
  late final GeneratedColumn<DateTime> startedAt = GeneratedColumn<DateTime>(
      'started_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _durationSecondsMeta =
      const VerificationMeta('durationSeconds');
  @override
  late final GeneratedColumn<int> durationSeconds = GeneratedColumn<int>(
      'duration_seconds', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns =>
      [id, otherUserId, callType, status, startedAt, durationSeconds];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'call_records_table';
  @override
  VerificationContext validateIntegrity(Insertable<CallRecordRow> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('other_user_id')) {
      context.handle(
          _otherUserIdMeta,
          otherUserId.isAcceptableOrUnknown(
              data['other_user_id']!, _otherUserIdMeta));
    } else if (isInserting) {
      context.missing(_otherUserIdMeta);
    }
    if (data.containsKey('call_type')) {
      context.handle(_callTypeMeta,
          callType.isAcceptableOrUnknown(data['call_type']!, _callTypeMeta));
    } else if (isInserting) {
      context.missing(_callTypeMeta);
    }
    if (data.containsKey('status')) {
      context.handle(_statusMeta,
          status.isAcceptableOrUnknown(data['status']!, _statusMeta));
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('started_at')) {
      context.handle(_startedAtMeta,
          startedAt.isAcceptableOrUnknown(data['started_at']!, _startedAtMeta));
    } else if (isInserting) {
      context.missing(_startedAtMeta);
    }
    if (data.containsKey('duration_seconds')) {
      context.handle(
          _durationSecondsMeta,
          durationSeconds.isAcceptableOrUnknown(
              data['duration_seconds']!, _durationSecondsMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CallRecordRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CallRecordRow(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      otherUserId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}other_user_id'])!,
      callType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}call_type'])!,
      status: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}status'])!,
      startedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}started_at'])!,
      durationSeconds: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}duration_seconds']),
    );
  }

  @override
  $CallRecordsTableTable createAlias(String alias) {
    return $CallRecordsTableTable(attachedDatabase, alias);
  }
}

class CallRecordRow extends DataClass implements Insertable<CallRecordRow> {
  final String id;
  final String otherUserId;
  final String callType;
  final String status;
  final DateTime startedAt;
  final int? durationSeconds;
  const CallRecordRow(
      {required this.id,
      required this.otherUserId,
      required this.callType,
      required this.status,
      required this.startedAt,
      this.durationSeconds});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['other_user_id'] = Variable<String>(otherUserId);
    map['call_type'] = Variable<String>(callType);
    map['status'] = Variable<String>(status);
    map['started_at'] = Variable<DateTime>(startedAt);
    if (!nullToAbsent || durationSeconds != null) {
      map['duration_seconds'] = Variable<int>(durationSeconds);
    }
    return map;
  }

  CallRecordsTableCompanion toCompanion(bool nullToAbsent) {
    return CallRecordsTableCompanion(
      id: Value(id),
      otherUserId: Value(otherUserId),
      callType: Value(callType),
      status: Value(status),
      startedAt: Value(startedAt),
      durationSeconds: durationSeconds == null && nullToAbsent
          ? const Value.absent()
          : Value(durationSeconds),
    );
  }

  factory CallRecordRow.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CallRecordRow(
      id: serializer.fromJson<String>(json['id']),
      otherUserId: serializer.fromJson<String>(json['otherUserId']),
      callType: serializer.fromJson<String>(json['callType']),
      status: serializer.fromJson<String>(json['status']),
      startedAt: serializer.fromJson<DateTime>(json['startedAt']),
      durationSeconds: serializer.fromJson<int?>(json['durationSeconds']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'otherUserId': serializer.toJson<String>(otherUserId),
      'callType': serializer.toJson<String>(callType),
      'status': serializer.toJson<String>(status),
      'startedAt': serializer.toJson<DateTime>(startedAt),
      'durationSeconds': serializer.toJson<int?>(durationSeconds),
    };
  }

  CallRecordRow copyWith(
          {String? id,
          String? otherUserId,
          String? callType,
          String? status,
          DateTime? startedAt,
          Value<int?> durationSeconds = const Value.absent()}) =>
      CallRecordRow(
        id: id ?? this.id,
        otherUserId: otherUserId ?? this.otherUserId,
        callType: callType ?? this.callType,
        status: status ?? this.status,
        startedAt: startedAt ?? this.startedAt,
        durationSeconds: durationSeconds.present
            ? durationSeconds.value
            : this.durationSeconds,
      );
  CallRecordRow copyWithCompanion(CallRecordsTableCompanion data) {
    return CallRecordRow(
      id: data.id.present ? data.id.value : this.id,
      otherUserId:
          data.otherUserId.present ? data.otherUserId.value : this.otherUserId,
      callType: data.callType.present ? data.callType.value : this.callType,
      status: data.status.present ? data.status.value : this.status,
      startedAt: data.startedAt.present ? data.startedAt.value : this.startedAt,
      durationSeconds: data.durationSeconds.present
          ? data.durationSeconds.value
          : this.durationSeconds,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CallRecordRow(')
          ..write('id: $id, ')
          ..write('otherUserId: $otherUserId, ')
          ..write('callType: $callType, ')
          ..write('status: $status, ')
          ..write('startedAt: $startedAt, ')
          ..write('durationSeconds: $durationSeconds')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id, otherUserId, callType, status, startedAt, durationSeconds);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CallRecordRow &&
          other.id == this.id &&
          other.otherUserId == this.otherUserId &&
          other.callType == this.callType &&
          other.status == this.status &&
          other.startedAt == this.startedAt &&
          other.durationSeconds == this.durationSeconds);
}

class CallRecordsTableCompanion extends UpdateCompanion<CallRecordRow> {
  final Value<String> id;
  final Value<String> otherUserId;
  final Value<String> callType;
  final Value<String> status;
  final Value<DateTime> startedAt;
  final Value<int?> durationSeconds;
  final Value<int> rowid;
  const CallRecordsTableCompanion({
    this.id = const Value.absent(),
    this.otherUserId = const Value.absent(),
    this.callType = const Value.absent(),
    this.status = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.durationSeconds = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CallRecordsTableCompanion.insert({
    required String id,
    required String otherUserId,
    required String callType,
    required String status,
    required DateTime startedAt,
    this.durationSeconds = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        otherUserId = Value(otherUserId),
        callType = Value(callType),
        status = Value(status),
        startedAt = Value(startedAt);
  static Insertable<CallRecordRow> custom({
    Expression<String>? id,
    Expression<String>? otherUserId,
    Expression<String>? callType,
    Expression<String>? status,
    Expression<DateTime>? startedAt,
    Expression<int>? durationSeconds,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (otherUserId != null) 'other_user_id': otherUserId,
      if (callType != null) 'call_type': callType,
      if (status != null) 'status': status,
      if (startedAt != null) 'started_at': startedAt,
      if (durationSeconds != null) 'duration_seconds': durationSeconds,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CallRecordsTableCompanion copyWith(
      {Value<String>? id,
      Value<String>? otherUserId,
      Value<String>? callType,
      Value<String>? status,
      Value<DateTime>? startedAt,
      Value<int?>? durationSeconds,
      Value<int>? rowid}) {
    return CallRecordsTableCompanion(
      id: id ?? this.id,
      otherUserId: otherUserId ?? this.otherUserId,
      callType: callType ?? this.callType,
      status: status ?? this.status,
      startedAt: startedAt ?? this.startedAt,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (otherUserId.present) {
      map['other_user_id'] = Variable<String>(otherUserId.value);
    }
    if (callType.present) {
      map['call_type'] = Variable<String>(callType.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (startedAt.present) {
      map['started_at'] = Variable<DateTime>(startedAt.value);
    }
    if (durationSeconds.present) {
      map['duration_seconds'] = Variable<int>(durationSeconds.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CallRecordsTableCompanion(')
          ..write('id: $id, ')
          ..write('otherUserId: $otherUserId, ')
          ..write('callType: $callType, ')
          ..write('status: $status, ')
          ..write('startedAt: $startedAt, ')
          ..write('durationSeconds: $durationSeconds, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PendingMediaUploadsTableTable extends PendingMediaUploadsTable
    with TableInfo<$PendingMediaUploadsTableTable, PendingMediaUploadRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PendingMediaUploadsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _localIdMeta =
      const VerificationMeta('localId');
  @override
  late final GeneratedColumn<String> localId = GeneratedColumn<String>(
      'local_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _filePathMeta =
      const VerificationMeta('filePath');
  @override
  late final GeneratedColumn<String> filePath = GeneratedColumn<String>(
      'file_path', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
      'type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _conversationIdMeta =
      const VerificationMeta('conversationId');
  @override
  late final GeneratedColumn<String> conversationId = GeneratedColumn<String>(
      'conversation_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _uploadedBytesMeta =
      const VerificationMeta('uploadedBytes');
  @override
  late final GeneratedColumn<int> uploadedBytes = GeneratedColumn<int>(
      'uploaded_bytes', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _totalBytesMeta =
      const VerificationMeta('totalBytes');
  @override
  late final GeneratedColumn<int> totalBytes = GeneratedColumn<int>(
      'total_bytes', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
      'status', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('pending'));
  @override
  List<GeneratedColumn> get $columns => [
        localId,
        filePath,
        type,
        conversationId,
        uploadedBytes,
        totalBytes,
        status
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'pending_media_uploads_table';
  @override
  VerificationContext validateIntegrity(
      Insertable<PendingMediaUploadRow> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('local_id')) {
      context.handle(_localIdMeta,
          localId.isAcceptableOrUnknown(data['local_id']!, _localIdMeta));
    } else if (isInserting) {
      context.missing(_localIdMeta);
    }
    if (data.containsKey('file_path')) {
      context.handle(_filePathMeta,
          filePath.isAcceptableOrUnknown(data['file_path']!, _filePathMeta));
    } else if (isInserting) {
      context.missing(_filePathMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
          _typeMeta, type.isAcceptableOrUnknown(data['type']!, _typeMeta));
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('conversation_id')) {
      context.handle(
          _conversationIdMeta,
          conversationId.isAcceptableOrUnknown(
              data['conversation_id']!, _conversationIdMeta));
    } else if (isInserting) {
      context.missing(_conversationIdMeta);
    }
    if (data.containsKey('uploaded_bytes')) {
      context.handle(
          _uploadedBytesMeta,
          uploadedBytes.isAcceptableOrUnknown(
              data['uploaded_bytes']!, _uploadedBytesMeta));
    }
    if (data.containsKey('total_bytes')) {
      context.handle(
          _totalBytesMeta,
          totalBytes.isAcceptableOrUnknown(
              data['total_bytes']!, _totalBytesMeta));
    } else if (isInserting) {
      context.missing(_totalBytesMeta);
    }
    if (data.containsKey('status')) {
      context.handle(_statusMeta,
          status.isAcceptableOrUnknown(data['status']!, _statusMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {localId};
  @override
  PendingMediaUploadRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PendingMediaUploadRow(
      localId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}local_id'])!,
      filePath: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}file_path'])!,
      type: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}type'])!,
      conversationId: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}conversation_id'])!,
      uploadedBytes: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}uploaded_bytes'])!,
      totalBytes: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}total_bytes'])!,
      status: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}status'])!,
    );
  }

  @override
  $PendingMediaUploadsTableTable createAlias(String alias) {
    return $PendingMediaUploadsTableTable(attachedDatabase, alias);
  }
}

class PendingMediaUploadRow extends DataClass
    implements Insertable<PendingMediaUploadRow> {
  final String localId;
  final String filePath;
  final String type;
  final String conversationId;
  final int uploadedBytes;
  final int totalBytes;
  final String status;
  const PendingMediaUploadRow(
      {required this.localId,
      required this.filePath,
      required this.type,
      required this.conversationId,
      required this.uploadedBytes,
      required this.totalBytes,
      required this.status});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['local_id'] = Variable<String>(localId);
    map['file_path'] = Variable<String>(filePath);
    map['type'] = Variable<String>(type);
    map['conversation_id'] = Variable<String>(conversationId);
    map['uploaded_bytes'] = Variable<int>(uploadedBytes);
    map['total_bytes'] = Variable<int>(totalBytes);
    map['status'] = Variable<String>(status);
    return map;
  }

  PendingMediaUploadsTableCompanion toCompanion(bool nullToAbsent) {
    return PendingMediaUploadsTableCompanion(
      localId: Value(localId),
      filePath: Value(filePath),
      type: Value(type),
      conversationId: Value(conversationId),
      uploadedBytes: Value(uploadedBytes),
      totalBytes: Value(totalBytes),
      status: Value(status),
    );
  }

  factory PendingMediaUploadRow.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PendingMediaUploadRow(
      localId: serializer.fromJson<String>(json['localId']),
      filePath: serializer.fromJson<String>(json['filePath']),
      type: serializer.fromJson<String>(json['type']),
      conversationId: serializer.fromJson<String>(json['conversationId']),
      uploadedBytes: serializer.fromJson<int>(json['uploadedBytes']),
      totalBytes: serializer.fromJson<int>(json['totalBytes']),
      status: serializer.fromJson<String>(json['status']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'localId': serializer.toJson<String>(localId),
      'filePath': serializer.toJson<String>(filePath),
      'type': serializer.toJson<String>(type),
      'conversationId': serializer.toJson<String>(conversationId),
      'uploadedBytes': serializer.toJson<int>(uploadedBytes),
      'totalBytes': serializer.toJson<int>(totalBytes),
      'status': serializer.toJson<String>(status),
    };
  }

  PendingMediaUploadRow copyWith(
          {String? localId,
          String? filePath,
          String? type,
          String? conversationId,
          int? uploadedBytes,
          int? totalBytes,
          String? status}) =>
      PendingMediaUploadRow(
        localId: localId ?? this.localId,
        filePath: filePath ?? this.filePath,
        type: type ?? this.type,
        conversationId: conversationId ?? this.conversationId,
        uploadedBytes: uploadedBytes ?? this.uploadedBytes,
        totalBytes: totalBytes ?? this.totalBytes,
        status: status ?? this.status,
      );
  PendingMediaUploadRow copyWithCompanion(
      PendingMediaUploadsTableCompanion data) {
    return PendingMediaUploadRow(
      localId: data.localId.present ? data.localId.value : this.localId,
      filePath: data.filePath.present ? data.filePath.value : this.filePath,
      type: data.type.present ? data.type.value : this.type,
      conversationId: data.conversationId.present
          ? data.conversationId.value
          : this.conversationId,
      uploadedBytes: data.uploadedBytes.present
          ? data.uploadedBytes.value
          : this.uploadedBytes,
      totalBytes:
          data.totalBytes.present ? data.totalBytes.value : this.totalBytes,
      status: data.status.present ? data.status.value : this.status,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PendingMediaUploadRow(')
          ..write('localId: $localId, ')
          ..write('filePath: $filePath, ')
          ..write('type: $type, ')
          ..write('conversationId: $conversationId, ')
          ..write('uploadedBytes: $uploadedBytes, ')
          ..write('totalBytes: $totalBytes, ')
          ..write('status: $status')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(localId, filePath, type, conversationId,
      uploadedBytes, totalBytes, status);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PendingMediaUploadRow &&
          other.localId == this.localId &&
          other.filePath == this.filePath &&
          other.type == this.type &&
          other.conversationId == this.conversationId &&
          other.uploadedBytes == this.uploadedBytes &&
          other.totalBytes == this.totalBytes &&
          other.status == this.status);
}

class PendingMediaUploadsTableCompanion
    extends UpdateCompanion<PendingMediaUploadRow> {
  final Value<String> localId;
  final Value<String> filePath;
  final Value<String> type;
  final Value<String> conversationId;
  final Value<int> uploadedBytes;
  final Value<int> totalBytes;
  final Value<String> status;
  final Value<int> rowid;
  const PendingMediaUploadsTableCompanion({
    this.localId = const Value.absent(),
    this.filePath = const Value.absent(),
    this.type = const Value.absent(),
    this.conversationId = const Value.absent(),
    this.uploadedBytes = const Value.absent(),
    this.totalBytes = const Value.absent(),
    this.status = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PendingMediaUploadsTableCompanion.insert({
    required String localId,
    required String filePath,
    required String type,
    required String conversationId,
    this.uploadedBytes = const Value.absent(),
    required int totalBytes,
    this.status = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : localId = Value(localId),
        filePath = Value(filePath),
        type = Value(type),
        conversationId = Value(conversationId),
        totalBytes = Value(totalBytes);
  static Insertable<PendingMediaUploadRow> custom({
    Expression<String>? localId,
    Expression<String>? filePath,
    Expression<String>? type,
    Expression<String>? conversationId,
    Expression<int>? uploadedBytes,
    Expression<int>? totalBytes,
    Expression<String>? status,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (localId != null) 'local_id': localId,
      if (filePath != null) 'file_path': filePath,
      if (type != null) 'type': type,
      if (conversationId != null) 'conversation_id': conversationId,
      if (uploadedBytes != null) 'uploaded_bytes': uploadedBytes,
      if (totalBytes != null) 'total_bytes': totalBytes,
      if (status != null) 'status': status,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PendingMediaUploadsTableCompanion copyWith(
      {Value<String>? localId,
      Value<String>? filePath,
      Value<String>? type,
      Value<String>? conversationId,
      Value<int>? uploadedBytes,
      Value<int>? totalBytes,
      Value<String>? status,
      Value<int>? rowid}) {
    return PendingMediaUploadsTableCompanion(
      localId: localId ?? this.localId,
      filePath: filePath ?? this.filePath,
      type: type ?? this.type,
      conversationId: conversationId ?? this.conversationId,
      uploadedBytes: uploadedBytes ?? this.uploadedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      status: status ?? this.status,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (localId.present) {
      map['local_id'] = Variable<String>(localId.value);
    }
    if (filePath.present) {
      map['file_path'] = Variable<String>(filePath.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (conversationId.present) {
      map['conversation_id'] = Variable<String>(conversationId.value);
    }
    if (uploadedBytes.present) {
      map['uploaded_bytes'] = Variable<int>(uploadedBytes.value);
    }
    if (totalBytes.present) {
      map['total_bytes'] = Variable<int>(totalBytes.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PendingMediaUploadsTableCompanion(')
          ..write('localId: $localId, ')
          ..write('filePath: $filePath, ')
          ..write('type: $type, ')
          ..write('conversationId: $conversationId, ')
          ..write('uploadedBytes: $uploadedBytes, ')
          ..write('totalBytes: $totalBytes, ')
          ..write('status: $status, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $MessagesTableTable messagesTable = $MessagesTableTable(this);
  late final $ConversationsTableTable conversationsTable =
      $ConversationsTableTable(this);
  late final $UsersTableTable usersTable = $UsersTableTable(this);
  late final $CallRecordsTableTable callRecordsTable =
      $CallRecordsTableTable(this);
  late final $PendingMediaUploadsTableTable pendingMediaUploadsTable =
      $PendingMediaUploadsTableTable(this);
  late final MessagesDao messagesDao = MessagesDao(this as AppDatabase);
  late final ConversationsDao conversationsDao =
      ConversationsDao(this as AppDatabase);
  late final UsersDao usersDao = UsersDao(this as AppDatabase);
  late final CallRecordsDao callRecordsDao =
      CallRecordsDao(this as AppDatabase);
  late final PendingMediaUploadsDao pendingMediaUploadsDao =
      PendingMediaUploadsDao(this as AppDatabase);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
        messagesTable,
        conversationsTable,
        usersTable,
        callRecordsTable,
        pendingMediaUploadsTable
      ];
}

typedef $$MessagesTableTableCreateCompanionBuilder = MessagesTableCompanion
    Function({
  required String id,
  required String conversationId,
  required String senderId,
  required String messageType,
  Value<String?> content,
  Value<String?> mediaLocalPath,
  Value<String?> mediaRemoteUrl,
  Value<String?> thumbnailUrl,
  Value<String> status,
  Value<String?> replyToId,
  required DateTime createdAt,
  Value<bool> isSynced,
  Value<bool> isDeleted,
  Value<int> rowid,
});
typedef $$MessagesTableTableUpdateCompanionBuilder = MessagesTableCompanion
    Function({
  Value<String> id,
  Value<String> conversationId,
  Value<String> senderId,
  Value<String> messageType,
  Value<String?> content,
  Value<String?> mediaLocalPath,
  Value<String?> mediaRemoteUrl,
  Value<String?> thumbnailUrl,
  Value<String> status,
  Value<String?> replyToId,
  Value<DateTime> createdAt,
  Value<bool> isSynced,
  Value<bool> isDeleted,
  Value<int> rowid,
});

class $$MessagesTableTableTableManager extends RootTableManager<
    _$AppDatabase,
    $MessagesTableTable,
    MessageRow,
    $$MessagesTableTableFilterComposer,
    $$MessagesTableTableOrderingComposer,
    $$MessagesTableTableCreateCompanionBuilder,
    $$MessagesTableTableUpdateCompanionBuilder> {
  $$MessagesTableTableTableManager(_$AppDatabase db, $MessagesTableTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          filteringComposer:
              $$MessagesTableTableFilterComposer(ComposerState(db, table)),
          orderingComposer:
              $$MessagesTableTableOrderingComposer(ComposerState(db, table)),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> conversationId = const Value.absent(),
            Value<String> senderId = const Value.absent(),
            Value<String> messageType = const Value.absent(),
            Value<String?> content = const Value.absent(),
            Value<String?> mediaLocalPath = const Value.absent(),
            Value<String?> mediaRemoteUrl = const Value.absent(),
            Value<String?> thumbnailUrl = const Value.absent(),
            Value<String> status = const Value.absent(),
            Value<String?> replyToId = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<bool> isSynced = const Value.absent(),
            Value<bool> isDeleted = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              MessagesTableCompanion(
            id: id,
            conversationId: conversationId,
            senderId: senderId,
            messageType: messageType,
            content: content,
            mediaLocalPath: mediaLocalPath,
            mediaRemoteUrl: mediaRemoteUrl,
            thumbnailUrl: thumbnailUrl,
            status: status,
            replyToId: replyToId,
            createdAt: createdAt,
            isSynced: isSynced,
            isDeleted: isDeleted,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String conversationId,
            required String senderId,
            required String messageType,
            Value<String?> content = const Value.absent(),
            Value<String?> mediaLocalPath = const Value.absent(),
            Value<String?> mediaRemoteUrl = const Value.absent(),
            Value<String?> thumbnailUrl = const Value.absent(),
            Value<String> status = const Value.absent(),
            Value<String?> replyToId = const Value.absent(),
            required DateTime createdAt,
            Value<bool> isSynced = const Value.absent(),
            Value<bool> isDeleted = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              MessagesTableCompanion.insert(
            id: id,
            conversationId: conversationId,
            senderId: senderId,
            messageType: messageType,
            content: content,
            mediaLocalPath: mediaLocalPath,
            mediaRemoteUrl: mediaRemoteUrl,
            thumbnailUrl: thumbnailUrl,
            status: status,
            replyToId: replyToId,
            createdAt: createdAt,
            isSynced: isSynced,
            isDeleted: isDeleted,
            rowid: rowid,
          ),
        ));
}

class $$MessagesTableTableFilterComposer
    extends FilterComposer<_$AppDatabase, $MessagesTableTable> {
  $$MessagesTableTableFilterComposer(super.$state);
  ColumnFilters<String> get id => $state.composableBuilder(
      column: $state.table.id,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get conversationId => $state.composableBuilder(
      column: $state.table.conversationId,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get senderId => $state.composableBuilder(
      column: $state.table.senderId,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get messageType => $state.composableBuilder(
      column: $state.table.messageType,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get content => $state.composableBuilder(
      column: $state.table.content,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get mediaLocalPath => $state.composableBuilder(
      column: $state.table.mediaLocalPath,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get mediaRemoteUrl => $state.composableBuilder(
      column: $state.table.mediaRemoteUrl,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get thumbnailUrl => $state.composableBuilder(
      column: $state.table.thumbnailUrl,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get status => $state.composableBuilder(
      column: $state.table.status,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get replyToId => $state.composableBuilder(
      column: $state.table.replyToId,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<DateTime> get createdAt => $state.composableBuilder(
      column: $state.table.createdAt,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<bool> get isSynced => $state.composableBuilder(
      column: $state.table.isSynced,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<bool> get isDeleted => $state.composableBuilder(
      column: $state.table.isDeleted,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));
}

class $$MessagesTableTableOrderingComposer
    extends OrderingComposer<_$AppDatabase, $MessagesTableTable> {
  $$MessagesTableTableOrderingComposer(super.$state);
  ColumnOrderings<String> get id => $state.composableBuilder(
      column: $state.table.id,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get conversationId => $state.composableBuilder(
      column: $state.table.conversationId,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get senderId => $state.composableBuilder(
      column: $state.table.senderId,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get messageType => $state.composableBuilder(
      column: $state.table.messageType,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get content => $state.composableBuilder(
      column: $state.table.content,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get mediaLocalPath => $state.composableBuilder(
      column: $state.table.mediaLocalPath,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get mediaRemoteUrl => $state.composableBuilder(
      column: $state.table.mediaRemoteUrl,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get thumbnailUrl => $state.composableBuilder(
      column: $state.table.thumbnailUrl,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get status => $state.composableBuilder(
      column: $state.table.status,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get replyToId => $state.composableBuilder(
      column: $state.table.replyToId,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<DateTime> get createdAt => $state.composableBuilder(
      column: $state.table.createdAt,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<bool> get isSynced => $state.composableBuilder(
      column: $state.table.isSynced,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<bool> get isDeleted => $state.composableBuilder(
      column: $state.table.isDeleted,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));
}

typedef $$ConversationsTableTableCreateCompanionBuilder
    = ConversationsTableCompanion Function({
  required String id,
  required String otherUserId,
  Value<String?> lastMessageId,
  required DateTime lastActivity,
  Value<int> unreadCount,
  Value<int> rowid,
});
typedef $$ConversationsTableTableUpdateCompanionBuilder
    = ConversationsTableCompanion Function({
  Value<String> id,
  Value<String> otherUserId,
  Value<String?> lastMessageId,
  Value<DateTime> lastActivity,
  Value<int> unreadCount,
  Value<int> rowid,
});

class $$ConversationsTableTableTableManager extends RootTableManager<
    _$AppDatabase,
    $ConversationsTableTable,
    ConversationRow,
    $$ConversationsTableTableFilterComposer,
    $$ConversationsTableTableOrderingComposer,
    $$ConversationsTableTableCreateCompanionBuilder,
    $$ConversationsTableTableUpdateCompanionBuilder> {
  $$ConversationsTableTableTableManager(
      _$AppDatabase db, $ConversationsTableTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          filteringComposer:
              $$ConversationsTableTableFilterComposer(ComposerState(db, table)),
          orderingComposer: $$ConversationsTableTableOrderingComposer(
              ComposerState(db, table)),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> otherUserId = const Value.absent(),
            Value<String?> lastMessageId = const Value.absent(),
            Value<DateTime> lastActivity = const Value.absent(),
            Value<int> unreadCount = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ConversationsTableCompanion(
            id: id,
            otherUserId: otherUserId,
            lastMessageId: lastMessageId,
            lastActivity: lastActivity,
            unreadCount: unreadCount,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String otherUserId,
            Value<String?> lastMessageId = const Value.absent(),
            required DateTime lastActivity,
            Value<int> unreadCount = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ConversationsTableCompanion.insert(
            id: id,
            otherUserId: otherUserId,
            lastMessageId: lastMessageId,
            lastActivity: lastActivity,
            unreadCount: unreadCount,
            rowid: rowid,
          ),
        ));
}

class $$ConversationsTableTableFilterComposer
    extends FilterComposer<_$AppDatabase, $ConversationsTableTable> {
  $$ConversationsTableTableFilterComposer(super.$state);
  ColumnFilters<String> get id => $state.composableBuilder(
      column: $state.table.id,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get otherUserId => $state.composableBuilder(
      column: $state.table.otherUserId,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get lastMessageId => $state.composableBuilder(
      column: $state.table.lastMessageId,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<DateTime> get lastActivity => $state.composableBuilder(
      column: $state.table.lastActivity,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<int> get unreadCount => $state.composableBuilder(
      column: $state.table.unreadCount,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));
}

class $$ConversationsTableTableOrderingComposer
    extends OrderingComposer<_$AppDatabase, $ConversationsTableTable> {
  $$ConversationsTableTableOrderingComposer(super.$state);
  ColumnOrderings<String> get id => $state.composableBuilder(
      column: $state.table.id,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get otherUserId => $state.composableBuilder(
      column: $state.table.otherUserId,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get lastMessageId => $state.composableBuilder(
      column: $state.table.lastMessageId,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<DateTime> get lastActivity => $state.composableBuilder(
      column: $state.table.lastActivity,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<int> get unreadCount => $state.composableBuilder(
      column: $state.table.unreadCount,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));
}

typedef $$UsersTableTableCreateCompanionBuilder = UsersTableCompanion Function({
  required String id,
  required String name,
  required String phone,
  Value<String?> avatarUrl,
  required DateTime lastSeen,
  Value<String> presence,
  Value<int> rowid,
});
typedef $$UsersTableTableUpdateCompanionBuilder = UsersTableCompanion Function({
  Value<String> id,
  Value<String> name,
  Value<String> phone,
  Value<String?> avatarUrl,
  Value<DateTime> lastSeen,
  Value<String> presence,
  Value<int> rowid,
});

class $$UsersTableTableTableManager extends RootTableManager<
    _$AppDatabase,
    $UsersTableTable,
    UserRow,
    $$UsersTableTableFilterComposer,
    $$UsersTableTableOrderingComposer,
    $$UsersTableTableCreateCompanionBuilder,
    $$UsersTableTableUpdateCompanionBuilder> {
  $$UsersTableTableTableManager(_$AppDatabase db, $UsersTableTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          filteringComposer:
              $$UsersTableTableFilterComposer(ComposerState(db, table)),
          orderingComposer:
              $$UsersTableTableOrderingComposer(ComposerState(db, table)),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<String> phone = const Value.absent(),
            Value<String?> avatarUrl = const Value.absent(),
            Value<DateTime> lastSeen = const Value.absent(),
            Value<String> presence = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              UsersTableCompanion(
            id: id,
            name: name,
            phone: phone,
            avatarUrl: avatarUrl,
            lastSeen: lastSeen,
            presence: presence,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String name,
            required String phone,
            Value<String?> avatarUrl = const Value.absent(),
            required DateTime lastSeen,
            Value<String> presence = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              UsersTableCompanion.insert(
            id: id,
            name: name,
            phone: phone,
            avatarUrl: avatarUrl,
            lastSeen: lastSeen,
            presence: presence,
            rowid: rowid,
          ),
        ));
}

class $$UsersTableTableFilterComposer
    extends FilterComposer<_$AppDatabase, $UsersTableTable> {
  $$UsersTableTableFilterComposer(super.$state);
  ColumnFilters<String> get id => $state.composableBuilder(
      column: $state.table.id,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get name => $state.composableBuilder(
      column: $state.table.name,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get phone => $state.composableBuilder(
      column: $state.table.phone,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get avatarUrl => $state.composableBuilder(
      column: $state.table.avatarUrl,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<DateTime> get lastSeen => $state.composableBuilder(
      column: $state.table.lastSeen,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get presence => $state.composableBuilder(
      column: $state.table.presence,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));
}

class $$UsersTableTableOrderingComposer
    extends OrderingComposer<_$AppDatabase, $UsersTableTable> {
  $$UsersTableTableOrderingComposer(super.$state);
  ColumnOrderings<String> get id => $state.composableBuilder(
      column: $state.table.id,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get name => $state.composableBuilder(
      column: $state.table.name,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get phone => $state.composableBuilder(
      column: $state.table.phone,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get avatarUrl => $state.composableBuilder(
      column: $state.table.avatarUrl,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<DateTime> get lastSeen => $state.composableBuilder(
      column: $state.table.lastSeen,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get presence => $state.composableBuilder(
      column: $state.table.presence,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));
}

typedef $$CallRecordsTableTableCreateCompanionBuilder
    = CallRecordsTableCompanion Function({
  required String id,
  required String otherUserId,
  required String callType,
  required String status,
  required DateTime startedAt,
  Value<int?> durationSeconds,
  Value<int> rowid,
});
typedef $$CallRecordsTableTableUpdateCompanionBuilder
    = CallRecordsTableCompanion Function({
  Value<String> id,
  Value<String> otherUserId,
  Value<String> callType,
  Value<String> status,
  Value<DateTime> startedAt,
  Value<int?> durationSeconds,
  Value<int> rowid,
});

class $$CallRecordsTableTableTableManager extends RootTableManager<
    _$AppDatabase,
    $CallRecordsTableTable,
    CallRecordRow,
    $$CallRecordsTableTableFilterComposer,
    $$CallRecordsTableTableOrderingComposer,
    $$CallRecordsTableTableCreateCompanionBuilder,
    $$CallRecordsTableTableUpdateCompanionBuilder> {
  $$CallRecordsTableTableTableManager(
      _$AppDatabase db, $CallRecordsTableTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          filteringComposer:
              $$CallRecordsTableTableFilterComposer(ComposerState(db, table)),
          orderingComposer:
              $$CallRecordsTableTableOrderingComposer(ComposerState(db, table)),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> otherUserId = const Value.absent(),
            Value<String> callType = const Value.absent(),
            Value<String> status = const Value.absent(),
            Value<DateTime> startedAt = const Value.absent(),
            Value<int?> durationSeconds = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              CallRecordsTableCompanion(
            id: id,
            otherUserId: otherUserId,
            callType: callType,
            status: status,
            startedAt: startedAt,
            durationSeconds: durationSeconds,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String otherUserId,
            required String callType,
            required String status,
            required DateTime startedAt,
            Value<int?> durationSeconds = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              CallRecordsTableCompanion.insert(
            id: id,
            otherUserId: otherUserId,
            callType: callType,
            status: status,
            startedAt: startedAt,
            durationSeconds: durationSeconds,
            rowid: rowid,
          ),
        ));
}

class $$CallRecordsTableTableFilterComposer
    extends FilterComposer<_$AppDatabase, $CallRecordsTableTable> {
  $$CallRecordsTableTableFilterComposer(super.$state);
  ColumnFilters<String> get id => $state.composableBuilder(
      column: $state.table.id,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get otherUserId => $state.composableBuilder(
      column: $state.table.otherUserId,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get callType => $state.composableBuilder(
      column: $state.table.callType,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get status => $state.composableBuilder(
      column: $state.table.status,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<DateTime> get startedAt => $state.composableBuilder(
      column: $state.table.startedAt,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<int> get durationSeconds => $state.composableBuilder(
      column: $state.table.durationSeconds,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));
}

class $$CallRecordsTableTableOrderingComposer
    extends OrderingComposer<_$AppDatabase, $CallRecordsTableTable> {
  $$CallRecordsTableTableOrderingComposer(super.$state);
  ColumnOrderings<String> get id => $state.composableBuilder(
      column: $state.table.id,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get otherUserId => $state.composableBuilder(
      column: $state.table.otherUserId,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get callType => $state.composableBuilder(
      column: $state.table.callType,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get status => $state.composableBuilder(
      column: $state.table.status,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<DateTime> get startedAt => $state.composableBuilder(
      column: $state.table.startedAt,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<int> get durationSeconds => $state.composableBuilder(
      column: $state.table.durationSeconds,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));
}

typedef $$PendingMediaUploadsTableTableCreateCompanionBuilder
    = PendingMediaUploadsTableCompanion Function({
  required String localId,
  required String filePath,
  required String type,
  required String conversationId,
  Value<int> uploadedBytes,
  required int totalBytes,
  Value<String> status,
  Value<int> rowid,
});
typedef $$PendingMediaUploadsTableTableUpdateCompanionBuilder
    = PendingMediaUploadsTableCompanion Function({
  Value<String> localId,
  Value<String> filePath,
  Value<String> type,
  Value<String> conversationId,
  Value<int> uploadedBytes,
  Value<int> totalBytes,
  Value<String> status,
  Value<int> rowid,
});

class $$PendingMediaUploadsTableTableTableManager extends RootTableManager<
    _$AppDatabase,
    $PendingMediaUploadsTableTable,
    PendingMediaUploadRow,
    $$PendingMediaUploadsTableTableFilterComposer,
    $$PendingMediaUploadsTableTableOrderingComposer,
    $$PendingMediaUploadsTableTableCreateCompanionBuilder,
    $$PendingMediaUploadsTableTableUpdateCompanionBuilder> {
  $$PendingMediaUploadsTableTableTableManager(
      _$AppDatabase db, $PendingMediaUploadsTableTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          filteringComposer: $$PendingMediaUploadsTableTableFilterComposer(
              ComposerState(db, table)),
          orderingComposer: $$PendingMediaUploadsTableTableOrderingComposer(
              ComposerState(db, table)),
          updateCompanionCallback: ({
            Value<String> localId = const Value.absent(),
            Value<String> filePath = const Value.absent(),
            Value<String> type = const Value.absent(),
            Value<String> conversationId = const Value.absent(),
            Value<int> uploadedBytes = const Value.absent(),
            Value<int> totalBytes = const Value.absent(),
            Value<String> status = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              PendingMediaUploadsTableCompanion(
            localId: localId,
            filePath: filePath,
            type: type,
            conversationId: conversationId,
            uploadedBytes: uploadedBytes,
            totalBytes: totalBytes,
            status: status,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String localId,
            required String filePath,
            required String type,
            required String conversationId,
            Value<int> uploadedBytes = const Value.absent(),
            required int totalBytes,
            Value<String> status = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              PendingMediaUploadsTableCompanion.insert(
            localId: localId,
            filePath: filePath,
            type: type,
            conversationId: conversationId,
            uploadedBytes: uploadedBytes,
            totalBytes: totalBytes,
            status: status,
            rowid: rowid,
          ),
        ));
}

class $$PendingMediaUploadsTableTableFilterComposer
    extends FilterComposer<_$AppDatabase, $PendingMediaUploadsTableTable> {
  $$PendingMediaUploadsTableTableFilterComposer(super.$state);
  ColumnFilters<String> get localId => $state.composableBuilder(
      column: $state.table.localId,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get filePath => $state.composableBuilder(
      column: $state.table.filePath,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get type => $state.composableBuilder(
      column: $state.table.type,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get conversationId => $state.composableBuilder(
      column: $state.table.conversationId,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<int> get uploadedBytes => $state.composableBuilder(
      column: $state.table.uploadedBytes,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<int> get totalBytes => $state.composableBuilder(
      column: $state.table.totalBytes,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get status => $state.composableBuilder(
      column: $state.table.status,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));
}

class $$PendingMediaUploadsTableTableOrderingComposer
    extends OrderingComposer<_$AppDatabase, $PendingMediaUploadsTableTable> {
  $$PendingMediaUploadsTableTableOrderingComposer(super.$state);
  ColumnOrderings<String> get localId => $state.composableBuilder(
      column: $state.table.localId,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get filePath => $state.composableBuilder(
      column: $state.table.filePath,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get type => $state.composableBuilder(
      column: $state.table.type,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get conversationId => $state.composableBuilder(
      column: $state.table.conversationId,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<int> get uploadedBytes => $state.composableBuilder(
      column: $state.table.uploadedBytes,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<int> get totalBytes => $state.composableBuilder(
      column: $state.table.totalBytes,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get status => $state.composableBuilder(
      column: $state.table.status,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));
}

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$MessagesTableTableTableManager get messagesTable =>
      $$MessagesTableTableTableManager(_db, _db.messagesTable);
  $$ConversationsTableTableTableManager get conversationsTable =>
      $$ConversationsTableTableTableManager(_db, _db.conversationsTable);
  $$UsersTableTableTableManager get usersTable =>
      $$UsersTableTableTableManager(_db, _db.usersTable);
  $$CallRecordsTableTableTableManager get callRecordsTable =>
      $$CallRecordsTableTableTableManager(_db, _db.callRecordsTable);
  $$PendingMediaUploadsTableTableTableManager get pendingMediaUploadsTable =>
      $$PendingMediaUploadsTableTableTableManager(
          _db, _db.pendingMediaUploadsTable);
}
