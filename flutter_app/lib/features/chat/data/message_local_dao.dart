import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/storage/local_db.dart';
import '../../../shared/models/message.dart';

/// Thin wrapper over the Drift [MessagesDao] + [ConversationsDao] that converts
/// between domain [Message] objects and the generated [MessageRow] companions.
class MessageLocalDao {
  final AppDatabase _db;

  MessageLocalDao(this._db);

  // ── Messages ──────────────────────────────────────────────────────────────

  Stream<List<Message>> watchMessages(String conversationId) {
    return _db.messagesDao
        .watchByConversation(conversationId)
        .map((rows) => rows.map(_rowToMessage).toList());
  }

  Future<List<Message>> getMessages(String conversationId) async {
    final rows = await _db.messagesDao.getByConversation(conversationId);
    return rows.map(_rowToMessage).toList();
  }

  Future<void> upsertMessage(Message msg) =>
      _db.messagesDao.upsert(_toCompanion(msg));

  Future<void> markSynced(String id) =>
      (_db.update(_db.messagesTable)..where((m) => m.id.equals(id))).write(
        const MessagesTableCompanion(
          isSynced: Value(true),
          status: Value('sent'),
        ),
      );

  Future<void> updateStatus(String id, MessageStatus status) =>
      (_db.update(_db.messagesTable)..where((m) => m.id.equals(id))).write(
        MessagesTableCompanion(status: Value(status.name)),
      );

  Future<void> markDeleted(String id) =>
      _db.messagesDao.markDeleted(id);

  // ── Conversations ─────────────────────────────────────────────────────────

  Stream<List<ConversationRow>> watchConversations() =>
      _db.conversationsDao.watchAll();

  Future<UserRow?> getUser(String userId) =>
      _db.usersDao.getById(userId);

  // ── Unread ────────────────────────────────────────────────────────────────

  Future<void> clearUnread(String conversationId) =>
      (_db.update(_db.conversationsTable)
            ..where((c) => c.id.equals(conversationId)))
          .write(const ConversationsTableCompanion(unreadCount: Value(0)));

  // ── Pending uploads ───────────────────────────────────────────────────────

  Future<List<PendingMediaUploadRow>> getPendingUploads() =>
      _db.pendingMediaUploadsDao.getPending();

  Future<void> upsertUpload(PendingMediaUploadsTableCompanion entry) =>
      _db.pendingMediaUploadsDao.upsert(entry);

  Future<void> markUploadDone(String localId) =>
      _db.pendingMediaUploadsDao.markDone(localId);

  // ── Converters ────────────────────────────────────────────────────────────

  Message _rowToMessage(MessageRow row) => Message(
        id: row.id,
        conversationId: row.conversationId,
        senderId: row.senderId,
        type: MessageType.values.firstWhere(
          (e) => e.name == row.messageType,
          orElse: () => MessageType.text,
        ),
        content: row.content,
        media: row.mediaRemoteUrl != null
            ? MediaAttachment(
                url: row.mediaRemoteUrl!,
                thumbnailUrl: row.thumbnailUrl,
              )
            : null,
        status: MessageStatus.values.firstWhere(
          (e) => e.name == row.status,
          orElse: () => MessageStatus.sent,
        ),
        createdAt: row.createdAt,
        replyToId: row.replyToId,
        isDeleted: row.isDeleted,
      );

  MessagesTableCompanion _toCompanion(Message msg) =>
      MessagesTableCompanion(
        id: Value(msg.id),
        conversationId: Value(msg.conversationId),
        senderId: Value(msg.senderId),
        messageType: Value(msg.type.name),
        content: Value(msg.content),
        mediaRemoteUrl: Value(msg.media?.url),
        thumbnailUrl: Value(msg.media?.thumbnailUrl),
        status: Value(msg.status.name),
        replyToId: Value(msg.replyToId),
        createdAt: Value(msg.createdAt),
        isSynced: Value(msg.status == MessageStatus.sent ||
            msg.status == MessageStatus.delivered ||
            msg.status == MessageStatus.read),
        isDeleted: Value(msg.isDeleted),
      );
}

final messageLocalDaoProvider = Provider<MessageLocalDao>((ref) {
  return MessageLocalDao(ref.watch(appDatabaseProvider));
});
