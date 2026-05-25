import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import '../../../shared/models/message.dart';

class MessageRepository {
  final Dio _dio;

  MessageRepository(this._dio);

  // ── Send ──────────────────────────────────────────────────────────────────

  Future<Message> sendMessage({
    required String clientId,
    required String conversationId,
    required MessageType type,
    String? content,
    String? mediaId,
    String? replyToId,
  }) async {
    final resp = await _dio.post<Map<String, dynamic>>(
      '/api/messages',
      data: {
        'id': clientId,
        'conversation_id': conversationId,
        'type': type.name,
        if (content != null) 'content': content,
        if (mediaId != null) 'media_id': mediaId,
        if (replyToId != null) 'reply_to_id': replyToId,
      },
    );
    return Message.fromJson(resp.data!);
  }

  // ── Fetch ─────────────────────────────────────────────────────────────────

  Future<List<Message>> fetchMessages(
    String conversationId, {
    String? cursor,
    int limit = 40,
  }) async {
    final resp = await _dio.get<Map<String, dynamic>>(
      '/api/conversations/$conversationId/messages',
      queryParameters: {
        'limit': limit,
        if (cursor != null) 'cursor': cursor,
      },
    );
    final items = (resp.data?['items'] as List<dynamic>?) ?? [];
    return items
        .map((e) => Message.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ── Receipts ──────────────────────────────────────────────────────────────

  Future<void> markDelivered(List<String> messageIds) async {
    if (messageIds.isEmpty) return;
    await _dio.post<void>(
      '/api/messages/delivered',
      data: {'message_ids': messageIds},
    );
  }

  Future<void> markRead(List<String> messageIds) async {
    if (messageIds.isEmpty) return;
    await _dio.post<void>(
      '/api/messages/read',
      data: {'message_ids': messageIds},
    );
  }

  // ── Delete ────────────────────────────────────────────────────────────────

  Future<void> deleteMessage(String messageId) async {
    await _dio.delete<void>('/api/messages/$messageId');
  }

  // ── Media upload ──────────────────────────────────────────────────────────

  /// Uploads a file and returns the `media_id` + signed URLs.
  /// [onProgress] reports (sent, total) bytes for the progress indicator.
  Future<MediaUploadResult> uploadMedia({
    required File file,
    required String type, // 'image' | 'video' | 'audio' | 'file'
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
        mediaId: json['media_id'] as String,
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
