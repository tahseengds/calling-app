import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/storage/local_db.dart';

class ConversationRepository {
  final Dio _dio;
  final AppDatabase _db;

  const ConversationRepository(this._dio, this._db);

  /// Returns the conversation ID for a 1-on-1 chat with [userId].
  ///
  /// Checks the local Drift cache first (instant, works offline).  If no
  /// local row exists the server is asked to get-or-create the conversation
  /// via `POST /api/conversations/` with `{user_id: userId}`.  The returned
  /// row is cached so the next call is always local.
  Future<String> getOrCreateConversation(String userId) async {
    final local = await _db.conversationsDao.findByOtherUserId(userId);
    if (local != null) return local.id;

    final resp = await _dio.post<Map<String, dynamic>>(
      '/api/conversations/',
      data: {'user_id': userId},
    );
    final json = resp.data!;
    final convId = json['id'] as String;

    // Cache so subsequent lookups are instant.
    await _db.conversationsDao.upsert(ConversationsTableCompanion(
      id: Value(convId),
      otherUserId: Value(userId),
      lastActivity: Value(
        json['last_activity'] != null
            ? DateTime.parse(json['last_activity'] as String).toLocal()
            : DateTime.now(),
      ),
    ));

    return convId;
  }
}

final conversationRepositoryProvider = Provider<ConversationRepository>((ref) {
  return ConversationRepository(
    ref.watch(dioProvider),
    ref.watch(appDatabaseProvider),
  );
});
