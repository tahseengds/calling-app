import 'dart:convert';

enum MessageType { text, image, video, audio, file, callLog }

enum MessageStatus { sending, sent, delivered, read, failed }

/// Wire string ↔ MessageType. We keep snake_case on the wire (matches the
/// rest of the REST API) but the Dart enum is camelCase, so the mapping
/// can't just rely on `.name`.
MessageType _parseMessageType(String? wire) {
  switch (wire) {
    case 'text':
      return MessageType.text;
    case 'image':
      return MessageType.image;
    case 'video':
      return MessageType.video;
    case 'audio':
      return MessageType.audio;
    case 'file':
      return MessageType.file;
    case 'call_log':
      return MessageType.callLog;
    default:
      return MessageType.text;
  }
}

String _messageTypeToWire(MessageType type) {
  switch (type) {
    case MessageType.text:
      return 'text';
    case MessageType.image:
      return 'image';
    case MessageType.video:
      return 'video';
    case MessageType.audio:
      return 'audio';
    case MessageType.file:
      return 'file';
    case MessageType.callLog:
      return 'call_log';
  }
}

/// Structured payload carried inside a [MessageType.callLog] message's
/// `content` field (as a JSON string). The backend inserts this when a
/// call ends; the chat renders it as an inline log entry.
///
/// `outcome` vocabulary (from backend/signaling/src/callLogMessage.js):
///   answered | missed | declined | busy | failed
class CallLogMeta {
  final String callType; // 'audio' | 'video'
  final String outcome;
  final int durationSeconds; // 0 when not answered

  const CallLogMeta({
    required this.callType,
    required this.outcome,
    required this.durationSeconds,
  });

  bool get isVideo => callType == 'video';
  bool get isAnswered => outcome == 'answered';
  bool get isMissed => outcome == 'missed';
  bool get isDeclined => outcome == 'declined';

  factory CallLogMeta.fromJson(Map<String, dynamic> json) => CallLogMeta(
        callType: json['call_type'] as String? ?? 'audio',
        outcome: json['outcome'] as String? ?? 'missed',
        durationSeconds: (json['duration_seconds'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'call_type': callType,
        'outcome': outcome,
        'duration_seconds': durationSeconds,
      };
}

/// Per-emoji aggregate of who reacted to a message. The server keeps the
/// authoritative state in `message_reactions`; this is the rolled-up shape
/// the client renders as chips. [userIds] lets the UI flag "you reacted"
/// and show a 'You and N others' tooltip on tap.
class ReactionSummary {
  final String emoji;
  final int count;
  final List<String> userIds;
  final DateTime firstReactedAt;

  const ReactionSummary({
    required this.emoji,
    required this.count,
    required this.userIds,
    required this.firstReactedAt,
  });

  bool reactedByUser(String userId) => userIds.contains(userId);

  factory ReactionSummary.fromJson(Map<String, dynamic> json) =>
      ReactionSummary(
        emoji: json['emoji'] as String,
        count: (json['count'] as num).toInt(),
        userIds: (json['user_ids'] as List<dynamic>)
            .map((e) => e as String)
            .toList(),
        firstReactedAt: DateTime.parse(json['first_reacted_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'emoji': emoji,
        'count': count,
        'user_ids': userIds,
        'first_reacted_at': firstReactedAt.toUtc().toIso8601String(),
      };
}

class ReplyPreview {
  final String senderName;
  final String text;

  const ReplyPreview({required this.senderName, required this.text});

  factory ReplyPreview.fromJson(Map<String, dynamic> json) => ReplyPreview(
        senderName: json['sender_name'] as String,
        text: json['text'] as String,
      );

  Map<String, dynamic> toJson() => {
        'sender_name': senderName,
        'text': text,
      };
}

class MediaAttachment {
  final String url;
  final String? thumbnailUrl;
  final String? mimeType;
  final int? sizeBytes;
  final int? durationSeconds;
  final int? width;
  final int? height;

  const MediaAttachment({
    required this.url,
    this.thumbnailUrl,
    this.mimeType,
    this.sizeBytes,
    this.durationSeconds,
    this.width,
    this.height,
  });

  factory MediaAttachment.fromJson(Map<String, dynamic> json) =>
      MediaAttachment(
        url: json['url'] as String,
        thumbnailUrl: json['thumbnail_url'] as String?,
        mimeType: json['mime_type'] as String?,
        sizeBytes: (json['file_size'] ?? json['size_bytes']) as int?,
        durationSeconds: json['duration_seconds'] as int?,
        width: json['width'] as int?,
        height: json['height'] as int?,
      );

  Map<String, dynamic> toJson() => {
        'url': url,
        if (thumbnailUrl != null) 'thumbnail_url': thumbnailUrl,
        if (mimeType != null) 'mime_type': mimeType,
        if (sizeBytes != null) 'size_bytes': sizeBytes,
        if (durationSeconds != null) 'duration_seconds': durationSeconds,
        if (width != null) 'width': width,
        if (height != null) 'height': height,
      };
}

class Message {
  final String id;
  final String conversationId;
  final String senderId;
  final MessageType type;
  final String? content;
  final MediaAttachment? media;
  final MessageStatus status;
  final DateTime createdAt;
  final String? replyToId;
  final ReplyPreview? replyTo;
  final bool isDeleted;
  /// Per-emoji aggregate of reactions on this message. Always empty for
  /// tombstones (the server scrubs reactions on soft-delete). Order is
  /// "first-reacted first" so chips don't shuffle as new emojis appear.
  final List<ReactionSummary> reactions;

  const Message({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.type,
    this.content,
    this.media,
    this.status = MessageStatus.sent,
    required this.createdAt,
    this.replyToId,
    this.replyTo,
    this.isDeleted = false,
    this.reactions = const [],
  });

  /// Lazily-decoded call-log metadata. Returns null for non-call_log
  /// messages or when `content` isn't valid JSON. Decoded on demand so
  /// regular bubbles don't pay the parse cost.
  CallLogMeta? get callLog {
    if (type != MessageType.callLog) return null;
    final c = content;
    if (c == null || c.isEmpty) return null;
    try {
      final decoded = jsonDecode(c);
      if (decoded is Map<String, dynamic>) {
        return CallLogMeta.fromJson(decoded);
      }
    } catch (_) {
      // Malformed — render the generic "Call" fallback in the UI.
    }
    return null;
  }

  factory Message.fromJson(Map<String, dynamic> json) => Message(
        id: json['id'] as String,
        conversationId: json['conversation_id'] as String,
        senderId: json['sender_id'] as String,
        type: _parseMessageType(
          (json['message_type'] as String?) ?? (json['type'] as String?),
        ),
        content: json['content'] as String?,
        media: json['media'] != null
            ? MediaAttachment.fromJson(
                json['media'] as Map<String, dynamic>,
              )
            : null,
        status: MessageStatus.values.firstWhere(
          (e) => e.name == (json['status'] as String? ?? 'sent'),
          orElse: () => MessageStatus.sent,
        ),
        createdAt: DateTime.parse(json['created_at'] as String),
        replyToId: json['reply_to_id'] as String?,
        replyTo: json['reply_to'] != null
            ? ReplyPreview.fromJson(json['reply_to'] as Map<String, dynamic>)
            : null,
        isDeleted: json['is_deleted'] as bool? ?? false,
        reactions: (json['reactions'] as List<dynamic>?)
                ?.map((e) =>
                    ReactionSummary.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'conversation_id': conversationId,
        'sender_id': senderId,
        'type': _messageTypeToWire(type),
        'message_type': _messageTypeToWire(type),
        if (content != null) 'content': content,
        if (media != null) 'media': media!.toJson(),
        'status': status.name,
        'created_at': createdAt.toUtc().toIso8601String(),
        if (replyToId != null) 'reply_to_id': replyToId,
        if (replyTo != null) 'reply_to': replyTo!.toJson(),
        'is_deleted': isDeleted,
        'reactions': reactions.map((r) => r.toJson()).toList(),
      };

  Message copyWith({
    MessageStatus? status,
    ReplyPreview? replyTo,
    List<ReactionSummary>? reactions,
  }) =>
      Message(
        id: id,
        conversationId: conversationId,
        senderId: senderId,
        type: type,
        content: content,
        media: media,
        status: status ?? this.status,
        createdAt: createdAt,
        replyToId: replyToId,
        replyTo: replyTo ?? this.replyTo,
        isDeleted: isDeleted,
        reactions: reactions ?? this.reactions,
      );
}
