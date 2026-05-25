import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../network/dio_client.dart';
import '../storage/local_db.dart';
import '../../shared/models/message.dart';

class SyncService {
  final AppDatabase _db;
  final Dio _dio;

  SyncService(this._db, this._dio);

  // ── Pending outbox ────────────────────────────────────────────────────────

  /// Re-sends messages that were written to Drift but never confirmed by the
  /// server (status = sending | pending | failed, isSynced = false).
  Future<void> syncPendingMessages() async {
    final rows = await (_db.select(_db.messagesTable)
          ..where((m) =>
              m.isSynced.equals(false) &
              m.status.isIn(['sending', 'pending', 'failed'])))
        .get();

    // Oldest first — preserve conversation ordering.
    rows.sort((a, b) => a.createdAt.compareTo(b.createdAt));

    for (final row in rows) {
      try {
        await _dio.post<void>(
          '/api/messages',
          data: {
            'id': row.id,
            'conversation_id': row.conversationId,
            'type': row.messageType,
            if (row.content != null) 'content': row.content,
            if (row.mediaRemoteUrl != null) 'media_url': row.mediaRemoteUrl,
            if (row.replyToId != null) 'reply_to_id': row.replyToId,
          },
        );
        await (_db.update(_db.messagesTable)
              ..where((m) => m.id.equals(row.id)))
            .write(const MessagesTableCompanion(
          isSynced: Value(true),
          status: Value('sent'),
        ));
      } catch (_) {
        // Leave as-is — retried on next reconnect.
      }
    }
  }

  // ── Missed messages ───────────────────────────────────────────────────────

  /// Fetches messages that arrived while the socket was down for one
  /// conversation.  Uses the most recent locally-stored message as a cursor.
  Future<void> fetchMissedMessages(String conversationId) async {
    final latest = await (_db.select(_db.messagesTable)
          ..where((m) => m.conversationId.equals(conversationId))
          ..orderBy([
            (m) =>
                OrderingTerm(expression: m.createdAt, mode: OrderingMode.desc)
          ])
          ..limit(1))
        .getSingleOrNull();

    final since = latest?.createdAt.toUtc().toIso8601String();

    try {
      final resp = await _dio.get<Map<String, dynamic>>(
        '/api/conversations/$conversationId/messages',
        queryParameters: since != null ? {'since': since} : null,
      );
      final items = (resp.data?['items'] as List<dynamic>?) ?? [];
      for (final item in items) {
        final msg = Message.fromJson(item as Map<String, dynamic>);
        await _db.messagesDao.upsert(_toCompanion(msg));
      }
    } catch (_) {
      // Best-effort; local cache is still usable.
    }
  }

  // ── Conversations ─────────────────────────────────────────────────────────

  /// Refreshes the conversation list and caches other-user profiles.
  Future<void> syncConversations() async {
    try {
      final resp =
          await _dio.get<Map<String, dynamic>>('/api/conversations');
      final items = (resp.data?['items'] as List<dynamic>?) ?? [];

      for (final item in items) {
        final json = item as Map<String, dynamic>;
        await _db.conversationsDao.upsert(ConversationsTableCompanion(
          id: Value(json['id'] as String),
          otherUserId: Value(json['other_user_id'] as String),
          lastMessageId: Value(json['last_message_id'] as String?),
          lastActivity: Value(
            DateTime.parse(json['last_activity'] as String).toLocal(),
          ),
          unreadCount: Value(json['unread_count'] as int? ?? 0),
        ));

        final u = json['other_user'] as Map<String, dynamic>?;
        if (u != null) {
          await _db.usersDao.upsert(UsersTableCompanion(
            id: Value(u['id'] as String),
            name: Value(u['name'] as String),
            phone: Value(u['phone'] as String? ?? ''),
            avatarUrl: Value(u['avatar_url'] as String?),
            lastSeen: Value(
              u['last_seen'] != null
                  ? DateTime.parse(u['last_seen'] as String).toLocal()
                  : DateTime.now(),
            ),
            presence: Value(u['presence'] as String? ?? 'offline'),
          ));
        }

        // Cache the last message if embedded.
        final lastMsg = json['last_message'] as Map<String, dynamic>?;
        if (lastMsg != null) {
          await _db.messagesDao
              .upsert(_toCompanion(Message.fromJson(lastMsg)));
        }
      }
    } catch (_) {
      // Tolerate network errors — local cache is returned to the UI.
    }
  }

  /// Convenience — called on reconnect and app resume.
  Future<void> syncAll(String conversationId) async {
    await Future.wait([
      syncConversations(),
      syncPendingMessages(),
      fetchMissedMessages(conversationId),
    ]);
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

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
        isSynced: const Value(true),
        isDeleted: Value(msg.isDeleted),
      );
}

final syncServiceProvider = Provider<SyncService>((ref) {
  return SyncService(
    ref.watch(appDatabaseProvider),
    ref.watch(dioProvider),
  );
});
