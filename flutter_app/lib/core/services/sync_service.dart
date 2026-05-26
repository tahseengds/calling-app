import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
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
        // Resolve recipient from the cached conversation.
        final convRows = await (_db.select(_db.conversationsTable)
              ..where((c) => c.id.equals(row.conversationId)))
            .get();
        final recipientId = convRows.firstOrNull?.otherUserId;
        if (recipientId == null) {
          // Conversation row evicted from cache (e.g. local DB wipe between
          // send and sync). Leave the message in the outbox so a future sync
          // can pick it up once the conversation list re-syncs from server.
          debugPrint(
              '[sync] skipping outbox message ${row.id}: conversation '
              '${row.conversationId} not in local cache');
          continue;
        }

        // Trailing slash required — see message_repository for rationale.
        await _dio.post<void>(
          '/api/messages/',
          data: {
            'client_id': row.id,
            'recipient_id': recipientId,
            'message_type': row.messageType,
            if (row.content != null) 'content': row.content,
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
    try {
      final resp = await _dio.get<Map<String, dynamic>>(
        '/api/conversations/$conversationId/messages',
        queryParameters: {'limit': 50},
      );
      // Backend returns MessagePage: { messages: [...], next_cursor: ... }
      final items = (resp.data?['messages'] as List<dynamic>?) ?? [];
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
      // Backend returns a bare JSON array of ConversationResponse objects.
      // Trailing slash required — see contact_repository for rationale.
      final resp = await _dio.get<List<dynamic>>('/api/conversations/');
      final items = resp.data ?? [];

      for (final item in items) {
        final json = item as Map<String, dynamic>;

        // 'other_user' is a nested UserPublic object, not a flat id field.
        final u = json['other_user'] as Map<String, dynamic>?;
        if (u == null) continue;

        await _db.conversationsDao.upsert(ConversationsTableCompanion(
          id: Value(json['id'] as String),
          otherUserId: Value(u['id'] as String),
          // 'last_message' is a nested MessageResponse (or null), not an id.
          lastMessageId: Value(
            (json['last_message'] as Map<String, dynamic>?)?['id'] as String?,
          ),
          lastActivity: Value(
            DateTime.parse(json['last_activity'] as String).toLocal(),
          ),
          unreadCount: Value(json['unread_count'] as int? ?? 0),
        ));

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

        // Cache the last message if embedded.
        final lastMsg = json['last_message'] as Map<String, dynamic>?;
        if (lastMsg != null) {
          await _db.messagesDao.upsert(_toCompanion(Message.fromJson(lastMsg)));
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
