import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

part 'local_db.g.dart';

// ── Tables ────────────────────────────────────────────────────────────────────

@DataClassName('MessageRow')
class MessagesTable extends Table {
  TextColumn get id => text()();
  TextColumn get conversationId => text()();
  TextColumn get senderId => text()();
  TextColumn get messageType => text()(); // mirrors MessageType.name
  TextColumn get content => text().nullable()();
  TextColumn get mediaLocalPath => text().nullable()();
  TextColumn get mediaRemoteUrl => text().nullable()();
  TextColumn get thumbnailUrl => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('sent'))();
  TextColumn get replyToId => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  BoolColumn get isSynced =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get isDeleted =>
      boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('ConversationRow')
class ConversationsTable extends Table {
  TextColumn get id => text()();
  TextColumn get otherUserId => text()();
  TextColumn get lastMessageId => text().nullable()();
  DateTimeColumn get lastActivity => dateTime()();
  IntColumn get unreadCount =>
      integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('UserRow')
class UsersTable extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get phone => text()();
  TextColumn get avatarUrl => text().nullable()();
  DateTimeColumn get lastSeen => dateTime()();
  TextColumn get presence =>
      text().withDefault(const Constant('offline'))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('CallRecordRow')
class CallRecordsTable extends Table {
  TextColumn get id => text()();
  TextColumn get otherUserId => text()();
  TextColumn get callType => text()();
  TextColumn get status => text()();
  DateTimeColumn get startedAt => dateTime()();
  IntColumn get durationSeconds => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

// Used by prompt 13 for resumable media uploads.
@DataClassName('PendingMediaUploadRow')
class PendingMediaUploadsTable extends Table {
  TextColumn get localId => text()();
  TextColumn get filePath => text()();
  TextColumn get type => text()(); // image | video | audio | file
  TextColumn get conversationId => text()();
  IntColumn get uploadedBytes =>
      integer().withDefault(const Constant(0))();
  IntColumn get totalBytes => integer()();
  TextColumn get status =>
      text().withDefault(const Constant('pending'))(); // pending | uploading | done | failed

  @override
  Set<Column> get primaryKey => {localId};
}

// ── DAOs ──────────────────────────────────────────────────────────────────────

@DriftAccessor(tables: [MessagesTable])
class MessagesDao extends DatabaseAccessor<AppDatabase>
    with _$MessagesDaoMixin {
  MessagesDao(super.db);

  Future<List<MessageRow>> getByConversation(String conversationId) =>
      (select(messagesTable)
            ..where((m) => m.conversationId.equals(conversationId))
            ..orderBy([(m) => OrderingTerm(expression: m.createdAt)]))
          .get();

  Stream<List<MessageRow>> watchByConversation(String conversationId) =>
      (select(messagesTable)
            ..where((m) => m.conversationId.equals(conversationId))
            ..orderBy([(m) => OrderingTerm(expression: m.createdAt)]))
          .watch();

  // Idempotent on id — safe to call for duplicate deliveries.
  Future<void> upsert(MessagesTableCompanion entry) =>
      into(messagesTable).insertOnConflictUpdate(entry);

  Future<void> markDeleted(String id) =>
      (update(messagesTable)..where((m) => m.id.equals(id)))
          .write(const MessagesTableCompanion(isDeleted: Value(true)));
}

@DriftAccessor(tables: [ConversationsTable])
class ConversationsDao extends DatabaseAccessor<AppDatabase>
    with _$ConversationsDaoMixin {
  ConversationsDao(super.db);

  Stream<List<ConversationRow>> watchAll() =>
      (select(conversationsTable)
            ..orderBy([
              (c) => OrderingTerm(
                    expression: c.lastActivity,
                    mode: OrderingMode.desc,
                  ),
            ]))
          .watch();

  Future<void> upsert(ConversationsTableCompanion entry) =>
      into(conversationsTable).insertOnConflictUpdate(entry);
}

@DriftAccessor(tables: [UsersTable])
class UsersDao extends DatabaseAccessor<AppDatabase> with _$UsersDaoMixin {
  UsersDao(super.db);

  Future<UserRow?> getById(String id) =>
      (select(usersTable)..where((u) => u.id.equals(id))).getSingleOrNull();

  Future<void> upsert(UsersTableCompanion entry) =>
      into(usersTable).insertOnConflictUpdate(entry);
}

@DriftAccessor(tables: [CallRecordsTable])
class CallRecordsDao extends DatabaseAccessor<AppDatabase>
    with _$CallRecordsDaoMixin {
  CallRecordsDao(super.db);

  Stream<List<CallRecordRow>> watchAll() =>
      (select(callRecordsTable)
            ..orderBy([
              (c) => OrderingTerm(
                    expression: c.startedAt,
                    mode: OrderingMode.desc,
                  ),
            ]))
          .watch();

  Future<void> upsert(CallRecordsTableCompanion entry) =>
      into(callRecordsTable).insertOnConflictUpdate(entry);
}

@DriftAccessor(tables: [PendingMediaUploadsTable])
class PendingMediaUploadsDao extends DatabaseAccessor<AppDatabase>
    with _$PendingMediaUploadsDaoMixin {
  PendingMediaUploadsDao(super.db);

  Future<List<PendingMediaUploadRow>> getPending() =>
      (select(pendingMediaUploadsTable)
            ..where((u) => u.status.isIn(['pending', 'uploading'])))
          .get();

  Future<void> upsert(PendingMediaUploadsTableCompanion entry) =>
      into(pendingMediaUploadsTable).insertOnConflictUpdate(entry);

  Future<void> markDone(String localId) =>
      (update(pendingMediaUploadsTable)
            ..where((u) => u.localId.equals(localId)))
          .write(
        const PendingMediaUploadsTableCompanion(status: Value('done')),
      );
}

// ── Database ──────────────────────────────────────────────────────────────────

@DriftDatabase(
  tables: [
    MessagesTable,
    ConversationsTable,
    UsersTable,
    CallRecordsTable,
    PendingMediaUploadsTable,
  ],
  daos: [
    MessagesDao,
    ConversationsDao,
    UsersDao,
    CallRecordsDao,
    PendingMediaUploadsDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// Opens an in-memory database — used exclusively in unit tests.
  ///
  /// ```dart
  /// import 'package:drift/native.dart';
  /// final db = AppDatabase.forTesting(NativeDatabase.memory());
  /// ```
  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        beforeOpen: (_) async {
          // WAL mode improves concurrent read performance.
          await customStatement('PRAGMA journal_mode=WAL');
        },
      );
}

QueryExecutor _openConnection() => driftDatabase(name: 'lumin_db');

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});
