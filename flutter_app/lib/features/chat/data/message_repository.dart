import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import '../../../shared/models/message.dart';

class MessageRepository {
  final Dio _dio;

  MessageRepository(this._dio);

  /// Backend message_type / upload type is
  /// 'text' | 'image' | 'video' | 'audio' | 'document'. The Dart enum spells
  /// the document variant `file`, so we translate at the wire boundary.
  static String wireType(MessageType type) =>
      type == MessageType.file ? 'document' : type.name;

  // ── Send ──────────────────────────────────────────────────────────────────

  Future<Message> sendMessage({
    required String clientId,
    required String recipientId,
    required MessageType type,
    String? content,
    String? mediaId,
    String? replyToId,
  }) async {
    // Trailing slash required — backend mounts POST at /api/messages/, and a
    // request to /api/messages would 307-redirect, dropping the Bearer header.
    final resp = await _dio.post<Map<String, dynamic>>(
      '/api/messages/',
      data: {
        'client_id': clientId,
        'recipient_id': recipientId,
        'message_type': wireType(type),
        'content': ?content,
        'media_id': ?mediaId,
        'reply_to_id': ?replyToId,
      },
    );
    return Message.fromJson(resp.data!);
  }

  // ── Fetch ─────────────────────────────────────────────────────────────────

  /// Fetches a page of messages (newest first). The backend returns both
  /// the page and an opaque [nextCursor] string — pass it back as `cursor`
  /// on the next call to load older messages. `nextCursor` is null when
  /// the conversation has been fully drained.
  Future<MessagePage> fetchMessages(
    String conversationId, {
    String? cursor,
    int limit = 40,
  }) async {
    final resp = await _dio.get<Map<String, dynamic>>(
      '/api/conversations/$conversationId/messages',
      queryParameters: {
        'limit': limit,
        'cursor': ?cursor,
      },
    );
    final data = resp.data ?? const <String, dynamic>{};
    final items = (data['messages'] as List<dynamic>?) ?? const [];
    return MessagePage(
      messages: items
          .map((e) => Message.fromJson(e as Map<String, dynamic>))
          .toList(),
      nextCursor: data['next_cursor'] as String?,
    );
  }

  // ── Receipts ──────────────────────────────────────────────────────────────

  Future<void> markDelivered(List<String> messageIds) async {
    if (messageIds.isEmpty) return;
    await _dio.put<void>(
      '/api/messages/delivered',
      data: {'message_ids': messageIds},
    );
  }

  Future<void> markRead(List<String> messageIds) async {
    if (messageIds.isEmpty) return;
    await _dio.put<void>(
      '/api/messages/read',
      data: {'message_ids': messageIds},
    );
  }

  // ── Delete ────────────────────────────────────────────────────────────────

  Future<void> deleteMessage(String messageId) async {
    await _dio.delete<void>('/api/messages/$messageId');
  }

  // ── Reactions ─────────────────────────────────────────────────────────────

  /// Add a reaction. Server is idempotent — calling twice with the same emoji
  /// just returns the unchanged summary.
  Future<List<ReactionSummary>> addReaction(
    String messageId,
    String emoji,
  ) async {
    final resp = await _dio.post<List<dynamic>>(
      '/api/messages/$messageId/reactions',
      data: {'emoji': emoji},
    );
    return (resp.data ?? const [])
        .map((e) => ReactionSummary.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Remove the current user's reaction for a given emoji. No-op server-side
  /// when it wasn't there to begin with — also returns the post-state summary.
  Future<List<ReactionSummary>> removeReaction(
    String messageId,
    String emoji,
  ) async {
    final resp = await _dio.delete<List<dynamic>>(
      '/api/messages/$messageId/reactions/${Uri.encodeComponent(emoji)}',
    );
    return (resp.data ?? const [])
        .map((e) => ReactionSummary.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ── Media upload ──────────────────────────────────────────────────────────

  /// Uploads a file and returns the `media_id` + signed URLs.
  /// [type] must be the *wire* type — `'image' | 'video' | 'audio' | 'document'`
  /// — not the Dart enum name. Use [wireType] or pass the literal directly.
  /// [onProgress] reports (sent, total) bytes for the progress indicator.
  Future<MediaUploadResult> uploadMedia({
    required File file,
    required String type,
    void Function(int sent, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(
        file.path,
        filename: file.path.split(Platform.pathSeparator).last,
      ),
      'type': type,
    });

    final resp = await _dio.post<Map<String, dynamic>>(
      '/api/media/upload',
      data: formData,
      cancelToken: cancelToken,
      onSendProgress: onProgress,
    );
    return MediaUploadResult.fromJson(resp.data!);
  }
}

/// A single page of messages from `/api/conversations/{id}/messages`.
///
/// [nextCursor] is opaque — pass it as the `cursor` query parameter on the
/// next request to load older messages. It encodes `(created_at, id)`
/// server-side; treating it as a message UUID would 500 the backend's
/// `decode_cursor`.
class MessagePage {
  final List<Message> messages;
  final String? nextCursor;

  const MessagePage({required this.messages, required this.nextCursor});
}


class MediaUploadResult {
  final String mediaId;
  final String url;
  final String? thumbnailUrl;
  final int? width;
  final int? height;
  final int? durationSeconds;

  const MediaUploadResult({
    required this.mediaId,
    required this.url,
    this.thumbnailUrl,
    this.width,
    this.height,
    this.durationSeconds,
  });

  factory MediaUploadResult.fromJson(Map<String, dynamic> json) =>
      MediaUploadResult(
        mediaId: json['id'] as String,
        url: json['url'] as String,
        thumbnailUrl: json['thumbnail_url'] as String?,
        width: json['width'] as int?,
        height: json['height'] as int?,
        durationSeconds: json['duration_seconds'] as int?,
      );

  MediaAttachment toAttachment() => MediaAttachment(
        url: url,
        thumbnailUrl: thumbnailUrl,
        width: width,
        height: height,
        durationSeconds: durationSeconds,
      );
}

final messageRepositoryProvider = Provider<MessageRepository>((ref) {
  return MessageRepository(ref.watch(dioProvider));
});
