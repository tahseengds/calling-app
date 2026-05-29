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
  // Length in seconds for audio + video. Round-tripped from the server's
  // ffprobe value; for unsent (optimistic) messages it holds the value the
  // recorder reported so the bubble can show the real length immediately.
  IntColumn get durationSeconds => integer().nullable()();
  TextColumn get status => text().withDefault(const Constant('sent'))();
  TextColumn get replyToId => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  BoolColumn get isSynced =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get isDeleted =>
      boolean().withDefault(const Constant(false))();
  /// JSON-encoded `List<ReactionSummary>` round-tripped from the server.
  /// Stored as JSON (not a separate join table) because the client only ever
  /// renders pre-aggregated chips — per-reaction queries aren't useful here.
  /// Empty string means "no reactions" (we avoid NULL so callers can decode
  /// without a null check on the hot read path).
  TextColumn get reactionsJson =>
      text().withDefault(const Constant(''))();

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

  /// Hard-remove a row — used when a never-sent optimistic message is
  /// cancelled (e.g. the user cancels a media upload mid-flight), so it
  /// vanishes entirely rather than leaving a "deleted" tombstone.
  Future<void> deleteById(String id) =>
      (delete(messagesTable)..where((m) => m.id.equals(id))).go();
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

  Future<ConversationRow?> findByOtherUserId(String userId) =>
      (select(conversationsTable)
            ..where((c) => c.otherUserId.equals(userId))
            ..limit(1))
          .getSingleOrNull();
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

  /// Update progress on an existing row without re-inserting it.
  /// Safe to call from the upload's progress callback — unlike [upsert],
  /// this never validates as an INSERT, so a partial companion will not
  /// throw when required columns (filePath, type, …) are absent.
  Future<void> updateProgress(
    String localId,
    int uploadedBytes, {
    String status = 'uploading',
  }) =>
      (update(pendingMediaUploadsTable)
            ..where((u) => u.localId.equals(localId)))
          .write(
        PendingMediaUploadsTableCompanion(
          uploadedBytes: Value(uploadedBytes),
          status: Value(status),
        ),
      );

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
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          // v1 → v2: messages gained a durationSeconds column for
          // audio/video bubbles. Existing rows backfill as NULL — only
          // newly-sent media will have a value populated.
          if (from < 2) {
            await m.addColumn(messagesTable, messagesTable.durationSeconds);
          }
          // v2 → v3: messages gained a reactionsJson column holding the
          // server's aggregated ReactionSummary list. Existing rows default
          // to '' which the DAO decodes as "no reactions".
          if (from < 3) {
            await m.addColumn(messagesTable, messagesTable.reactionsJson);
          }
        },
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
