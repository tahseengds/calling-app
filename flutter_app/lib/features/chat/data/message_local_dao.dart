import 'dart:convert';

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

  Future<void> deleteMessage(String id) =>
      _db.messagesDao.deleteById(id);

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

  // ── Edit / Pin / Disappearing ───────────────────────────────────────────────

  /// Update a message's content + mark it edited (text edits).
  Future<void> setEdited(String id, String content, DateTime editedAt) =>
      (_db.update(_db.messagesTable)..where((m) => m.id.equals(id))).write(
        MessagesTableCompanion(
          content: Value(content),
          editedAt: Value(editedAt),
        ),
      );

  /// Pin / unpin a message. Passing null unpins it.
  Future<void> setPinned(String id, DateTime? pinnedAt) =>
      (_db.update(_db.messagesTable)..where((m) => m.id.equals(id)))
          .write(MessagesTableCompanion(pinnedAt: Value(pinnedAt)));

  /// Set/clear a single message's disappearing expiry.
  Future<void> setExpiresAt(String id, DateTime? expiresAt) =>
      (_db.update(_db.messagesTable)..where((m) => m.id.equals(id)))
          .write(MessagesTableCompanion(expiresAt: Value(expiresAt)));

  /// Hard-delete every message in a conversation whose expiry has passed —
  /// the client-side half of disappearing messages.
  Future<void> purgeExpired(String conversationId, DateTime now) =>
      (_db.delete(_db.messagesTable)
            ..where((m) =>
                m.conversationId.equals(conversationId) &
                m.expiresAt.isSmallerOrEqualValue(now)))
          .go();

  /// Read the conversation's disappearing TTL (seconds), or null if disabled.
  Future<int?> getDisappearingSeconds(String conversationId) async {
    final row = await (_db.select(_db.conversationsTable)
          ..where((c) => c.id.equals(conversationId)))
        .getSingleOrNull();
    return row?.disappearingSeconds;
  }

  /// Set/clear the conversation's disappearing TTL.
  Future<void> setDisappearingSeconds(String conversationId, int? seconds) =>
      (_db.update(_db.conversationsTable)
            ..where((c) => c.id.equals(conversationId)))
          .write(
              ConversationsTableCompanion(disappearingSeconds: Value(seconds)));

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
                durationSeconds: row.durationSeconds,
              )
            : null,
        status: MessageStatus.values.firstWhere(
          (e) => e.name == row.status,
          orElse: () => MessageStatus.sent,
        ),
        createdAt: row.createdAt,
        replyToId: row.replyToId,
        isDeleted: row.isDeleted,
        reactions: decodeReactions(row.reactionsJson),
        editedAt: row.editedAt,
        pinnedAt: row.pinnedAt,
        expiresAt: row.expiresAt,
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
        durationSeconds: Value(msg.media?.durationSeconds),
        status: Value(msg.status.name),
        replyToId: Value(msg.replyToId),
        createdAt: Value(msg.createdAt),
        isSynced: Value(msg.status == MessageStatus.sent ||
            msg.status == MessageStatus.delivered ||
            msg.status == MessageStatus.read),
        isDeleted: Value(msg.isDeleted),
        reactionsJson: Value(encodeReactions(msg.reactions)),
        editedAt: Value(msg.editedAt),
        pinnedAt: Value(msg.pinnedAt),
        expiresAt: Value(msg.expiresAt),
      );

  // ── Reactions ─────────────────────────────────────────────────────────────

  /// Replace a single message's stored reactions list. Used by the realtime
  /// event handler — the server gives us the post-mutation aggregate, so we
  /// can blindly overwrite instead of mutating individual rows.
  Future<void> updateReactions(
    String messageId,
    List<ReactionSummary> reactions,
  ) =>
      (_db.update(_db.messagesTable)..where((m) => m.id.equals(messageId)))
          .write(
        MessagesTableCompanion(
          reactionsJson: Value(encodeReactions(reactions)),
        ),
      );
}

/// Encode a reaction list as the compact JSON we store in `reactionsJson`.
/// Empty list → empty string so the column default works without a null path.
String encodeReactions(List<ReactionSummary> reactions) {
  if (reactions.isEmpty) return '';
  return jsonEncode(reactions.map((r) => r.toJson()).toList());
}

/// Decode the inverse. Tolerates the empty-string sentinel + any parse error
/// (e.g. row written by a future schema) by returning an empty list.
List<ReactionSummary> decodeReactions(String? raw) {
  if (raw == null || raw.isEmpty) return const [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return decoded
        .map((e) => ReactionSummary.fromJson(e as Map<String, dynamic>))
        .toList();
  } catch (_) {
    return const [];
  }
}

final messageLocalDaoProvider = Provider<MessageLocalDao>((ref) {
  return MessageLocalDao(ref.watch(appDatabaseProvider));
});
